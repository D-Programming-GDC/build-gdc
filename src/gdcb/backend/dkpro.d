module gdcb.backend.dkpro;

import gdcb.backend.base, gdcb.builder, gdcb.config, gdcb.util;
import vibe.data.json;
import std.path, std.string, std.stdio, std.algorithm, std.exception,
    std.datetime, std.array, std.process;
import std.file : exists, readText, dirEntries, SpanMode;

struct BackendConfig
{
    string srcURL;
    string gccVersion;
    string complibs;
    string dkName;
    string baseToolchain;
    string filename;
    @optional string gdbVersion;
}

class DKProBackend : Backend
{
private:
    bool _verbose;
    GitID[GCCVersion] _sourceInfo;

public:
    void initialize(GitID[GCCVersion] sourceInfo, bool verbose)
    {
        _verbose = verbose;
        _sourceInfo = sourceInfo;
        auto srcFolder = configuration.sharedFolder.buildPath("sources", "dkPro");
        tryMkdir(srcFolder);
    }

    DKProBuild createInstance(Toolchain toolchain)
    {
        return new DKProBuild(this, toolchain);
    }

    string getType()
    {
        return "dkPro";
    }
}

string downloadCache(string url)
{
    return downloadCache(url, "dkPro");
}

string downloadCache(string url, string folder)
{
    import std.array;

    return downloadCache(url, folder, split(url, '/')[$ - 1]);
}

string downloadCache(string url, string folder, string fileName)
{
    string filePath = configuration.sharedFolder.buildPath("sources", folder, fileName);

    if (!exists(filePath))
    {
        writeln("Downloading file");
        execute("wget", "-nv", url, "-O", filePath);
    }

    return filePath;
}

class DKProBuild : BuildInstance
{
private:
    DKProBackend _backend;
    Toolchain _toolchain;
    BackendConfig _backendConfig;
    string _dependsFolder, _prebuiltFolder;

    SourceInfo setupGDC()
    {
        writeln(": Preparing GDC");
        GitID gdcID;

        switch (_backendConfig.gccVersion[0 .. 3])
        {
        case "4.7":
            gdcID = _backend._sourceInfo[GCCVersion.V4_7];
            break;
        case "4.8":
            gdcID = _backend._sourceInfo[GCCVersion.V4_8];
            break;
        case "4.9":
            gdcID = _backend._sourceInfo[GCCVersion.V4_9];
            break;
        default:
            switch (_backendConfig.gccVersion[0 .. 1])
            {
            case "5":
                gdcID = _backend._sourceInfo[GCCVersion.V5];
                break;
            default:
                enforce(false, format("Unknown GCC version '%s'", _backendConfig.gccVersion));
            }
        }

        chdir(configuration.gdcFolder);
        execute("git", "checkout", gdcID.value);

        SourceInfo info;
        info.gdcRevision = chomp(std.process.execute(["git", "rev-parse", "HEAD"]).output);
        info.dmdFE = chomp(readText(configuration.gdcFolder.buildPath("gcc", "d", "VERSION"))).replace("\"",
            "");
        info.gccVersion = _backendConfig.gccVersion;
        info.date = Clock.currTime;

        return info;
    }

    string setupCompLibs()
    {
        writeln(": Setting up comp libs");
        auto compLibs = downloadCache(_backendConfig.complibs);

        chdir(configuration.tmpFolder);
        execute("tar", "xf", compLibs);
        return configuration.tmpFolder.buildPath("complibs");
    }

    string setupBuildTools()
    {
        writeln(": Setting up build tools");
        auto buildScripts = downloadCache(_backendConfig.srcURL);

        chdir(configuration.tmpFolder);
        execute("tar", "xf", buildScripts);
        return configuration.tmpFolder.buildPath("buildscripts");
    }

    string[] buildDependencyPath()
    {
        string[] path;
        foreach (entry; dirEntries(_dependsFolder, SpanMode.shallow))
        {
            path ~= entry.buildPath("bin");
        }
        return path;
    }

    void finishArchive()
    {
        // Create archive
        string extension = "tar.xz";
        if (_toolchain.config.host.triplet.canFind("mingw"))
            extension = "7z";
        _toolchain.filename = format(_backendConfig.filename, _toolchain.source.dmdFE,
            extension);

        auto dkProFolder = configuration.tmpFolder.buildPath("dkPro");
        auto installFolder = configuration.tmpFolder.buildPath(_backendConfig.dkName);

        string dkSubDir;
        foreach (entry; dkProFolder.dirEntries(SpanMode.breadth))
        {
            if (baseName(entry.name) == _backendConfig.dkName && entry.isDir)
            {
                dkSubDir = entry.name;
                break;
            }
        }

        string[] files;
        string[] glob = ["*libexec/gcc/*/*/cc1d*", "*bin/*gdc*"];
        foreach (entry; dkSubDir.dirEntries(SpanMode.breadth))
        {
            foreach (gentry; glob)
            {
                if (entry.name.globMatch(gentry))
                    files ~= entry.name;
            }
        }

        foreach (entry; files)
        {
            string namePart = entry.relativePath(dkSubDir);
            string dest = installFolder.buildPath(namePart.dirName);
            tryMkdir(dest);
            execute("cp", entry, dest);
        }

        if (!_backendConfig.gdbVersion.empty)
            execute("cp", "-R", dkSubDir.buildPath("gdb-" ~ _backendConfig.gdbVersion), installFolder);

        copyExtraFiles(_toolchain.config.path, installFolder);

        chdir(configuration.tmpFolder);
        createArchive(installFolder.relativePath(configuration.tmpFolder), _toolchain.resultFile);
    }

public:
    this(DKProBackend backend, Toolchain toolchain)
    {
        _backend = backend;
        _toolchain = toolchain;
        _dependsFolder = configuration.tmpFolder.buildPath("depends");
        _prebuiltFolder = configuration.tmpFolder.buildPath("prebuilt-native-tools");
        deserializeJson(_backendConfig, _toolchain.config.backendConfig);
    }

    /**
     * Calculate dependencies for this toolchain.
     */
    string[] calculateDependencies()
    {
        return _toolchain.config.depends;
    }

    /**
     * Setup temporary build folders.
     */
    void initilize()
    {
        tryMkdir(_dependsFolder);
    }

    /**
     * Install Dependecies.
     */
    void installDependencies(Toolchain[] dependencies)
    {
        chdir(_dependsFolder);

        if (_toolchain.config.host.triplet != "x86_64-linux-gnu")
        {
            auto baseToolchainPath = downloadCache(_backendConfig.baseToolchain);

            execute("tar", "xf", baseToolchainPath);
        }
        foreach (depend; dependencies)
        {
            execute("tar", "xf", depend.resultFile);
        }
    }

    /**
     * Start the ctng build process.
     */
    void build()
    {
        auto scriptFolder = setupBuildTools();
        auto compLibs = setupCompLibs();
        chdir(scriptFolder);

        execute("patch", "-p1", "-i", _toolchain.config.path.buildPath("gdc.diff"));
        _toolchain.source = setupGDC();
        chdir(scriptFolder);

        string[] dependsPath = buildDependencyPath();
        auto env = environment.toAA();
        if (dependsPath.length > 0)
            env["PATH"] = environment.get("PATH") ~ ":" ~ dependsPath.join(":");

        switch (_toolchain.config.host.triplet)
        {
        case "x86_64-linux-gnu":
            break;
        default:
            env["CROSSBUILD"] = _toolchain.config.host.triplet;
        }
        env["COMP_LIBS"] = compLibs;
        env["DMD_FE"] = _toolchain.source.dmdFE;
        env["GDC_REV"] = _toolchain.source.gdcRevision;

        execute(env, "./build-devkit.sh");

        finishArchive();

        _toolchain.specialToolchainName = _backendConfig.dkName;
        _toolchain.downloadInfo["filename"] = _toolchain.filename;
        _toolchain.downloadInfo["comment"] = _toolchain.config.comment;
        _toolchain.downloadInfo["runtime"] = _toolchain.config.runtime;
        _toolchain.downloadInfo["dmdFE"] = _toolchain.source.dmdFE;
        _toolchain.downloadInfo["md5Sum"] = _toolchain.md5Sum;
    }

    /**
     * Remove temporary files.
     */
    void cleanup()
    {
        tryRemove(_dependsFolder);
    }
}
