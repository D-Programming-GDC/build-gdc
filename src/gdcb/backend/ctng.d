module gdcb.backend.ctng;

import std.array, std.path, std.exception, std.stdio;
import std.string : format;
import file = std.file;

import gdcb.backend.base, gdcb.builder, gdcb.config, gdcb.util;

class CTNGBackend : Backend
{
private:
    GitID[GCCVersion] _sourceInfo;
    SourceInfo[string] _cachedSources;
    string[string] _cachedSourceTarballs;
    string _extractFolder, _buildFolder, _installFolder, _dependsFolder, _sourceFolder;
    string _vanillaFolder, _snapshotFolder;
    bool _verbose;

    string getSourcePath(string ver)
    {
        return _cachedSourceTarballs[ver];
    }

    SourceInfo loadSource(string ver)
    {
        writefln(": Loading source for gcc-%s", ver);
        if (ver in _cachedSources)
        {
            writeln("    => cached");
            return _cachedSources[ver];
        }
        else
        {
            writeln("    => preparing source");
            string tarball;
            auto src = prepareSource(ver, tarball);
            _cachedSources[ver] = src;
            _cachedSourceTarballs[ver] = tarball;
            return src;
        }
    }

    SourceInfo prepareSource(string ver, out string tarballDest)
    {
        import std.string, std.array, std.datetime;

        enforce(ver.length > 2, "Unknown GCC version");
        GitID gdcID = _sourceInfo[ver.toGCCVersion()];

        chdir(configuration.gdcFolder);
        execute("git", "checkout", gdcID.value);

        string gccName;
        string gccURL;
        string tarballName;
        if (ver == "custom")
        {
            gccName = chomp(file.readText(configuration.gdcFolder.buildPath("gcc.version")));
            tarballName = gccName ~ ".tar.bz2";
            gccURL = format("http://ftp.gwdg.de/pub/misc/gcc/snapshots/%s/%s",
                gccName[4 .. $], tarballName);
        }
        else
        {
            gccName = "gcc-" ~ ver;
            tarballName = gccName ~ ".tar.bz2";
            gccURL = format("http://ftp.gwdg.de/pub/misc/gcc/releases/%s/%s", gccName,
                tarballName);
        }

        string gccPath = _extractFolder.buildPath(gccName);
        string tarballPath = _vanillaFolder.buildPath(tarballName);

        writeln(": Extracting gcc");
        tryRemove(gccPath);
        chdir(_extractFolder);

        if (!file.exists(tarballPath))
        {
            writeln("Downloading vanilla gcc");
            execute("wget", "-nv", gccURL, "-O", tarballPath);
        }

        execute("tar", "xf", tarballPath);
        string extractedPath = _extractFolder.buildPath(gccName);
        scope (exit)
        {
            writeln(": Cleaning up temporary files");
            tryRemove(extractedPath);
        }
        checkExists(extractedPath);

        writeln(": Patching gcc");
        chdir(configuration.gdcFolder);
        execute("./setup-gcc.sh", extractedPath);
        SourceInfo info;
        info.gdcRevision = chomp(std.process.execute(["git", "rev-parse", "HEAD"]).output);
        info.dmdFE = chomp(file.readText(configuration.gdcFolder.buildPath("gcc",
            "d", "VERSION"))).replace("\"", "");
        if (ver == "custom")
            info.gccVersion = gccName[4 .. $];
        else
            info.gccVersion = ver;
        info.date = Clock.currTime;

        writeln(": Creating gcc tarball");
        string newGCCTarball = _sourceFolder.buildPath(gccName ~ ".tar.gz");
        chdir(_extractFolder);
        tryRemove(newGCCTarball);
        execute("tar", "zcfh", newGCCTarball, gccName);
        tarballDest = newGCCTarball;

        return info;
    }

public:
    void initialize(GitID[GCCVersion] sourceInfo, bool verbose)
    {
        _verbose = verbose;
        _sourceInfo = sourceInfo;
        _extractFolder = configuration.tmpFolder.buildPath("gcc");
        _buildFolder = configuration.tmpFolder.buildPath("build");
        _installFolder = configuration.tmpFolder.buildPath("install");
        _dependsFolder = configuration.tmpFolder.buildPath("depends");
        _sourceFolder = configuration.sharedFolder.buildPath("sources");
        _vanillaFolder = _sourceFolder.buildPath("vanilla");
        _snapshotFolder = configuration.tmpFolder.buildPath("gcc-snapshot");

        tryMkdir(_sourceFolder);
        tryMkdir(_vanillaFolder);
    }

    CTNGBuild createInstance(Toolchain toolchain)
    {
        return new CTNGBuild(this, toolchain);
    }

    string getType()
    {
        return "ctng";
    }
}

class CTNGBuild : BuildInstance
{
private:
    CTNGBackend _backend;
    Toolchain _toolchain;
    Toolchain[] _dependencies;
    string snapshotPath;

    /**
     * Gets the used GCC version from the ctng .config file.
     */
    string findGCCVersion()
    {
        import std.regex;

        auto confFile = _toolchain.config.path.buildPath(".config");
        auto conf = file.readText(confFile);
        return matchFirst(conf, "CT_CC_GCC_VERSION=\"(?P<ver>.+)\"")["ver"];
    }

    /**
     * Gets the executable paths for the dependecies.
     */
    string[] buildDependencyPath()
    {
        string[] path;
        foreach (entry; file.dirEntries(_backend._dependsFolder, file.SpanMode.shallow))
        {
            path ~= entry.buildPath("bin");
        }
        return path;
    }

    /**
     * Update the ctng .config file CT_TOOLCHAIN_PKGVERSION and CT_CC_CUSTOM_LOCATION
     * 
     */
    void updateConfig()
    {
        import std.file, std.array;

        string confString = readText(".config");
        string newVersion = format("CT_TOOLCHAIN_PKGVERSION=\"%04d%02d%02d-%s-%s\"",
            _toolchain.source.date.year, _toolchain.source.date.month,
            _toolchain.source.date.day, _toolchain.source.dmdFE,
            _toolchain.source.gdcRevision[0 .. 10]);

        confString = confString.replace("CT_TOOLCHAIN_PKGVERSION=\"\"", newVersion);
        if (snapshotPath.length)
        {
            confString = confString.replace("CT_CC_GCC_CUSTOM_LOCATION=\"\"",
                format("CT_CC_GCC_CUSTOM_LOCATION=\"%s\"", snapshotPath));
        }
        File confFile = File(".config", "w");
        confFile.rawWrite(confString);
        confFile.close();
    }

    /**
     * CTNG places files in _backend._installFolder/$CT_TARGET.
     * Return full path to this folder.
     */
    string findCTNGInstallFolder()
    {
        import std.file;

        foreach (entry; dirEntries(_backend._installFolder, SpanMode.shallow))
        {
            if (isDir(entry))
                return entry;
        }
        enforce(false, "CTNG Install folder not found");
        return "";
    }

public:
    this(CTNGBackend backend, Toolchain toolchain)
    {
        _backend = backend;
        _toolchain = toolchain;
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
        tryRemove(_backend._buildFolder);
        mkdir(_backend._buildFolder);

        tryRemove(_backend._installFolder);
        mkdir(_backend._installFolder);

        tryRemove(_backend._dependsFolder);
        mkdir(_backend._dependsFolder);

        tryRemove(_backend._snapshotFolder);
        mkdir(_backend._snapshotFolder);

        tryRemove(_backend._snapshotFolder);
        mkdir(_backend._extractFolder);
    }

    /**
     * Install Dependecies.
     */
    void installDependencies(Toolchain[] dependencies)
    {
        _dependencies = dependencies;
        chdir(_backend._dependsFolder);
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
        import std.process : environment;
        import std.array : join;

        writeln(": CTNG backend started");
        string[] path = buildDependencyPath();
        if (_backend._verbose)
            writefln(": Dependency path: %s", path);
        string ver = findGCCVersion();
        if (_backend._verbose)
            writefln(": GCC version: %s", ver);

        _toolchain.source = _backend.loadSource(ver);
        if (ver == "custom")
        {
            chdir(_backend._snapshotFolder);
            execute(["tar", "xf", _backend.getSourcePath(ver)]);
            snapshotPath = _backend._snapshotFolder.buildPath(
                baseName(_backend.getSourcePath(ver), ".tar.gz"));
        }

        // Copy configuration to temporary folder
        copyContents(_toolchain.config.path, _backend._buildFolder);

        chdir(_backend._buildFolder);
        writeln(": Updating .config file");
        updateConfig();

        // Prepare PATH
        auto env = environment.toAA();
        if (path.length > 0)
            env["PATH"] = environment.get("PATH") ~ ":" ~ path.join(":");

        if (_backend._verbose)
            writefln(": Environment for ctng: %s", env);

        // Do the build
        try
        {
            execute(env, ["ct-ng", "build"]);
        }
        catch (Exception e)
        {
            import std.file;

            copy(_backend._buildFolder.buildPath("build.log"),
                _toolchain.resultPath.buildPath("build.log"));
            throw e;
        }

        string installFolder = findCTNGInstallFolder();
        // Build GDMD
        auto gdmd = buildGDMD(_toolchain.config.host.triplet,
            _toolchain.config.host.triplet == _toolchain.config.target,
            _toolchain.config.gdmdRev, ver.toGCCVersion());
        installGDMD(gdmd, installFolder);

        // Copy extra files
        writeln(": Copying extra files");
        if (_backend._verbose)
            writefln(": Install folder: %s", installFolder);
        copyExtraFiles(_toolchain.config.path, installFolder);
        saveBuildInfo(_toolchain.config, _toolchain.source, installFolder);

        // Create archive
        writeln(": Creating archive");
        _toolchain.filename = generateFileName(_toolchain);
        if (_backend._verbose)
            writefln("    => filename: %s", _toolchain.filename);

        chdir(_backend._installFolder);
        createArchive(installFolder.relativePath(_backend._installFolder), _toolchain.resultFile);
    }

    /**
     * Remove temporary files.
     */
    void cleanup()
    {
        tryRemove(_backend._buildFolder);
        tryRemove(_backend._installFolder);
        tryRemove(_backend._dependsFolder);
        tryRemove(_backend._snapshotFolder);
        tryRemove(_backend._extractFolder);
    }
}
