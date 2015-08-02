module gdcb.backend.armEmbedded;

import gdcb.backend.base, gdcb.builder, gdcb.config, gdcb.util;
import vibe.data.json;
import std.path, std.string, std.stdio, std.algorithm, std.exception,
    std.datetime, std.array;
import std.file : exists, readText;

struct BackendConfig
{
    string srcURL;
    string gccVersion;
    string nativeTools;
    string pythonURL;
}

class ArmEmbeddedBackend : Backend
{
private:
    bool _verbose;
    GitID[GCCVersion] _sourceInfo;

public:
    void initialize(GitID[GCCVersion] sourceInfo, bool verbose)
    {
        _verbose = verbose;
        _sourceInfo = sourceInfo;
        auto dependsFolder = configuration.sharedFolder.buildPath("sources", "gcc-arm-embedded");
        tryMkdir(dependsFolder);
    }

    ArmEmbeddedBuild createInstance(Toolchain toolchain)
    {
        return new ArmEmbeddedBuild(this, toolchain);
    }

    string getType()
    {
        return "gcc-arm-embedded";
    }
}

string downloadCache(string url)
{
    return downloadCache(url, "gcc-arm-embedded");
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

class ArmEmbeddedBuild : BuildInstance
{
private:
    ArmEmbeddedBackend _backend;
    Toolchain _toolchain;
    BackendConfig _backendConfig;
    string _dependsFolder, _prebuiltFolder, _embeddedSrc;
    bool _isMinGWBuild = false;

    SourceInfo setupGDC()
    {
        writeln(": Patching gcc");
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
        execute("./setup-gcc.sh", _embeddedSrc.buildPath("src", "gcc"));

        SourceInfo info;
        info.gdcRevision = chomp(std.process.execute(["git", "rev-parse", "HEAD"]).output);
        info.dmdFE = chomp(readText(configuration.gdcFolder.buildPath("gcc", "d", "VERSION"))).replace("\"",
            "");
        info.gccVersion = _backendConfig.gccVersion;
        info.date = Clock.currTime;

        return info;
    }

    void buildPython()
    {
        string pythonFile = downloadCache(_backendConfig.pythonURL);
        chdir(configuration.tmpFolder);
        execute("tar", "xf", pythonFile);

        string configure = configuration.tmpFolder.buildPath(
            pythonFile.stripExtension().baseName(), "configure");
        string pythonBuildFolder = configuration.tmpFolder.buildPath("python-build");
        mkdir(pythonBuildFolder);
        chdir(pythonBuildFolder);

        execute(configure, format("--prefix=%s",
            _prebuiltFolder.buildPath("python")), "--enable-unicode=ucs4", "--enable-shared");
        execute("make", "-j2");
        execute("make", "install");
    }

    void setupBuildTools()
    {
        writeln(": Setting up build tools");
        auto toolsFile = downloadCache(_backendConfig.nativeTools);

        chdir(configuration.tmpFolder);
        execute("tar", "xf", toolsFile);
        chdir(_prebuiltFolder);
        tryRemove("gcc");
        tryRemove("python");
        execute("mv", _dependsFolder.buildPath("x86_64-pc-linux-gnu"), "gcc");
        string minGWPath = _dependsFolder.buildPath("x86_64-w64-mingw32");

        if (exists(minGWPath))
        {
            _isMinGWBuild = true;
            tryRemove("mingw-w64-gcc");
            execute("mv", minGWPath, "mingw-w64-gcc");
        }

        mkdir("python");
        buildPython();
    }

    string findFilename()
    {
        import std.file;

        chdir("pkg");
        foreach (entry; dirEntries(".", SpanMode.shallow))
        {
            if (entry.isFile)
            {
                if (_isMinGWBuild)
                {
                    if (entry.name.canFind(".exe") && !entry.name.canFind("jammer"))
                        return entry.name.baseName(".exe");
                }
                else
                {
                    if (entry.name.canFind("linux.tar.bz2"))
                        return entry.name.baseName(".tar.bz2");
                }
            }
        }

        throw new Exception("Result package not found");
    }

public:
    this(ArmEmbeddedBackend backend, Toolchain toolchain)
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
        setupBuildTools();

        auto srcFile = downloadCache(_backendConfig.srcURL);
        chdir(configuration.tmpFolder);
        execute("tar", "xf", srcFile);
        auto srcFolder = srcFile.baseName(".tar.bz2")[0 .. $ - 4];
        _embeddedSrc = configuration.tmpFolder.buildPath(srcFolder);
        chdir(_embeddedSrc);

        execute("patch", "-p1", "-i", _toolchain.config.path.buildPath("gdc.diff"));
        chdir("src");
        executeShell("find -name '*.tar.*' | xargs -I% tar -xf %");

        _toolchain.source = setupGDC();
        chdir(_embeddedSrc);

        if (_isMinGWBuild)
        {
            execute("./build-prerequisites.sh",
                "--build_tools=/home/build/tmp/prebuilt-native-tools");
            execute("./build-toolchain.sh", "--build_tools=/home/build/tmp/prebuilt-native-tools");
        }
        else
        {
            execute("./build-prerequisites.sh",
                "--build_tools=/home/build/tmp/prebuilt-native-tools", "--skip_steps=mingw32");
            execute("./build-toolchain.sh",
                "--build_tools=/home/build/tmp/prebuilt-native-tools", "--skip_steps=mingw32");
        }

        auto baseName = findFilename();
        if (_isMinGWBuild)
        {
            _toolchain.filename = baseName ~ ".exe";
            execute("mv", baseName ~ ".exe", _toolchain.resultPath);
            execute("mv", baseName ~ ".zip", _toolchain.resultPath);
        }
        else
        {
            _toolchain.filename = baseName ~ ".tar.bz2";
            execute("mv", baseName ~ ".tar.bz2", _toolchain.resultPath);
        }
    }

    /**
     * Remove temporary files.
     */
    void cleanup()
    {
        tryRemove(_dependsFolder);
    }
}
