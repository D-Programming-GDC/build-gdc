module gdcb.backend.base;

import std.datetime;
import gdcb.builder, gdcb.config, gdcb.util;

/**
 * Contains information about used GDC source
 */
struct SourceInfo
{
    string gdcRevision, dmdFE, gccVersion;
    SysTime date; //Source preparation date
}

struct BuildInfo
{
    ToolchainConfig config;
    SourceInfo source;
}

/**
 * Backend entry point. Created once per application.
 */
interface Backend
{
    /**
     * Initialize directory structure etc.
     */
    void initialize(GitID[GCCVersion] sourceInfo, bool verbose);

    /**
     * Create a build instance.
     */
    BuildInstance createInstance(Toolchain toolchain);

    /**
     * Return the type tag used in config.json
     */
    string getType();
}

/**
 * Created for every toolchain build.
 */
interface BuildInstance
{
    /**
     * Called first, returns toolchains which need to be build
     * before this toolchain.
     */
    string[] calculateDependencies();

    /**
     * Called first to start a build.
     * Setup folders etc.
     */
    void initilize();

    /**
     * Called before build. Should install all the required toolchains
     * for the build step (e.g. unpack them).
     */
    void installDependencies(Toolchain[] dependencies);

    /**
     * Build the toolchain.
     * Note: Source preparation should probably be cached.
     * Must update toolchain.source.
     */
    void build();

    /**
     * Called after build, even if build failed.
     * Remove temporary files, etc.
     */
    void cleanup();
}

/**
 * Copy custom additional files from config folder.
 */
void copyExtraFiles(string configPath, string targetPath)
{
    import std.file, std.path;

    string extraPath = configPath.buildPath("extra-files");

    if (extraPath.exists())
    {
        foreach (entry; dirEntries(extraPath, SpanMode.breadth))
        {
            auto relEntry = relativePath(entry, extraPath);
            if (isFile(entry))
                copy(entry.name, targetPath.buildPath(relEntry));
            else if (isDir(entry))
                mkdir(targetPath.buildPath(relEntry));
        }
    }
}

/**
 * Save information about this build into gdc.json file.
 */
void saveBuildInfo(ToolchainConfig config, SourceInfo source, string folder)
{
    import std.path, std.stdio, vibe.data.json;

    auto info = BuildInfo(config, source);

    auto jfile = File(folder.buildPath("gdc.json"), "w");
    auto writer = jfile.lockingTextWriter();
    writePrettyJsonString(writer, serializeToJson(info));
    jfile.close();
}

/**
 * Generate the result archive filename.
 * 7z for windows hosts, tar.xz for rest.
 */
string generateFileName(Toolchain toolchain)
{
    import std.algorithm : canFind;

    string extension = "tar.xz";
    if (toolchain.config.host.triplet.canFind("mingw"))
        extension = "7z";

    auto config = toolchain.config;
    auto source = toolchain.source;
    return format("%s_%s_gcc%s_%s_%04d%02d%02d.%s", config.target,
        source.dmdFE, source.gccVersion, source.gdcRevision[0 .. 10],
        source.date.year, source.date.month, source.date.day, extension);
}

/**
 * Compress folder at srcdir into file at resultFile.
 * File must be a .7z or .tar.xz file.
 */
void createArchive(string srcdir, string resultFile)
{
    import std.algorithm : endsWith;
    import std.string : format;

    if (resultFile.endsWith(".7z"))
        execute("7zr", "a", "-l", "-mx9", resultFile, srcdir);
    else if (resultFile.endsWith(".tar.xz"))
        executeShell(format("tar -cf - %s | xz -9 -c - > %s", srcdir, resultFile));
    else
        assert(false, "Invalid file extension");
}
