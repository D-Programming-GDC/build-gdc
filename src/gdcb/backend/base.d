module gdcb.backend.base;

import std.datetime, std.exception, std.stdio, std.path;
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

GCCVersion toGCCVersion(string ver)
{
    if (ver == "custom")
    {
        return GCCVersion.snapshot;
    }
    else
    {
        switch (ver[0 .. 3])
        {
        case "4.7":
            return GCCVersion.V4_7;
        case "4.8":
            return GCCVersion.V4_8;
        case "4.9":
            return GCCVersion.V4_9;
        default:
            switch (ver[0 .. 1])
            {
            case "5":
                return GCCVersion.V5;
            default:
                enforce(false, format("Unknown GCC version '%s'", ver));
            }
        }
    }
    assert(0);
}

/**
 * Build GDMD for host.
 * Params:
 *     host = host identifier used to find a host compiler
 *     ver = version of GDMD to build.
 *     gccVer = gcc version to be used by GDMD
 * Returns:
 *     path to the compiled file in a temporary directory.
 */
string buildGDMD(string host, bool isNative, string ver, GCCVersion gccVer)
{
    import std.process : environment;

    writeln(": Building GDMD");
    string gccConfig;
    final switch (gccVer)
    {
    case GCCVersion.snapshot:
        gccConfig = "gdc7";
        break;
    case GCCVersion.V5:
        gccConfig = "gdc5";
        break;
    case GCCVersion.V4_9:
        gccConfig = "gdc4.9";
        break;
    case GCCVersion.V4_8:
        gccConfig = "gdc4.8";
        break;
    case GCCVersion.V4_7:
        assert(0);
    }

    // FIXME: No windows cross compiler, use precompiled binaries
    if (host == "i686-w64-mingw32" || host == "x86_64-w64-mingw32")
    {
        writeln(": Use precompiled GDMD for windows hosts");
        return configuration.sharedFolder.buildPath("gdmd-bin",
            host ~ "-" ~ gccConfig ~ "-" ~ ver ~ "-gdmd.exe");
    }

    string compiler = "/home/build/host-gdc/".buildPath(host, "bin", host ~ "-gdc");
    chdir(configuration.gdmdFolder);
    execute("git", "checkout", ver, "-f");

    auto env = environment.toAA();
    if (isNative)
        env["DFLAGS"] = "-fversion=UseSystemAR";
    execute(env, "dub", "build", "-f", "--compiler=" ~ compiler,
        "--config=" ~ gccConfig);

    auto stripPath = "/home/build/host-gdc/".buildPath(host, "bin", host ~ "-strip");
    if (host == "x86_64-linux-gnu")
        stripPath = "strip";

    string resultFile = configuration.gdmdFolder.buildPath("gdmd");
    execute(stripPath, resultFile);

    return resultFile;
}

void installGDMD(string gdmd, string installFolder)
{
    import std.file, std.algorithm, std.array;

    string installedGDMD;
    foreach (DirEntry entry; installFolder.dirEntries(SpanMode.breadth))
    {
        if (entry.isFile && entry.name.canFind("gdc"))
        {
            writefln(": Installing GDMD for %s", entry.name);
            string target = entry.name.replace("gdc", "gdmd");
            if (installedGDMD.empty)
            {
                copy(gdmd, target);
                installedGDMD = target;
            }
            else
            {
                chdir(target.dirName());
                execute("ln", "-s",
                    installedGDMD.relativePath(target.dirName()), target.baseName());
            }
            execute("chmod", "+x", target);
        }
    }
}
