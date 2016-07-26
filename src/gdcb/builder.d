module gdcb.builder;

import core.time;
import std.concurrency, std.file, std.exception, std.path, std.stdio,
    vibe.data.json;
import std.algorithm, std.range;
import std.string : format;
import gdcb.config, gdcb.util, gdcb.website;
import gdcb.backend.base, gdcb.backend.ctng, gdcb.backend.armEmbedded,
    gdcb.backend.dkpro;

/**
 *
 */
class Builder
{
private:
    DownloadSite website;

    // The toolchains we actually want to build
    Toolchain[] _target;
    // Complete ordered queue, including dependecies. Might contain duplicates
    Toolchain[][] _buildQueue;
    // List of already finished builds
    Toolchain[string] _buildCache;

    // List of available Backends
    Backend[] _backends;

    /**
     * Initialize the builder field in toolchain
     */
    void setBuilder(Toolchain toolchain)
    {
        auto backendR = find!"a.getType() == b"(_backends, toolchain.config.backend);
        enforce(!backendR.empty, format("Unknown backend %s", toolchain.config.backend));
        auto backend = backendR.front;

        toolchain.builder = backend.createInstance(toolchain);
    }

    /**
     * Put all dependencies of toolchain and toolchain into array
     * in correct order.
     */
    Toolchain[] addDependencies(Toolchain toolchain, ref string[] pending)
    {
        Toolchain[] result;

        if (pending.canFind(toolchain.toolchainID))
            throw new Exception(format("Circular dependency: %s=>%s", pending,
                toolchain.toolchainID));
        pending ~= toolchain.toolchainID;

        foreach (id; toolchain.builder.calculateDependencies())
        {
            auto depends = Toolchain.load(id, true);
            setBuilder(depends);
            result ~= addDependencies(depends, pending);
        }
        pending = pending[0 .. $ - 1];
        result ~= toolchain;
        return result;
    }

    void updateGDMD()
    {
        writeln(": Updating GDMD");
        gdcb.util.chdir(configuration.gdmdFolder);
        execute("git", "remote", "update");
    }

    void updateGDC()
    {
        writeln(": Updating GDC");
        gdcb.util.chdir(configuration.gdcFolder);
        execute("git", "remote", "update");
    }

    void updateConfigs()
    {
        writeln(": Updating build-gdc-config");
        gdcb.util.chdir(configuration.configBaseFolder);
        execute("git", "remote", "update");
    }

    void checkoutConfigs(GitID id)
    {
        writeln(": Checking out build-gdc-config");
        gdcb.util.chdir(configuration.configBaseFolder);
        execute("git", "checkout", id.value);
    }

    /**
     * Calculate dependencies and do the build.
     * 
     * Returns:
     *     false if one or more toolchains failed to build.
     */
    bool build()
    {
        scope (exit)
            gdcb.util.remove(configuration.resultTMPFolder);
        // Setup queue
        writeln("Calculating dependencies");
        foreach (toolchain; _target)
        {
            string[] tmp;
            auto dependencies = addDependencies(toolchain, tmp);
            if (verbose)
                writefln("    * '%s' => '%s'", toolchain.toolchainID, dependencies);
            _buildQueue ~= dependencies;
        }

        // Fixup dependencyOnly field of dependencies which we also want to keep
        foreach (set; _buildQueue)
        {
            foreach (entry; set)
            {
                if (_target.canFind!"a.toolchainID == b.toolchainID"(entry))
                    entry.dependencyOnly = false;
            }
        }

        if (verbose)
            writeln("Dumping build queue: ", _buildQueue);

        writeln();
        writeln();
        writeln("===============================================================================");

        Toolchain[] failedToolchains;
        Toolchain[] succeededToolchains;
        foreach (set; _buildQueue)
        {
            writefln(": Building toolchain %s", set[$ - 1].toolchainID);
            foreach (entry; set[0 .. $ - 1])
            {
                if (entry.toolchainID in _buildCache)
                {
                    writefln(": Dependecy %s in cache", entry.toolchainID);
                }
                else
                {
                    writefln(": Building dependecy %s", entry.toolchainID);
                    build(entry);
                    _buildCache[entry.toolchainID] = entry;
                }
            }

            auto entry = set[$ - 1];
            if (entry.toolchainID in _buildCache)
            {
                entry = *(entry.toolchainID in _buildCache);
                writefln(": Toolchain %s in cache", entry.toolchainID);
            }
            else
            {
                writefln(": Now building toolchain %s", entry.toolchainID);
                build(entry);
                _buildCache[entry.toolchainID] = entry;
            }

            if (entry.failed)
            {
                failedToolchains ~= entry;
            }
            else
            {
                website.addToolchain(entry);
                succeededToolchains ~= entry;
            }

            writeln();
            writeln(
                "-------------------------------------------------------------------------------");
        }

        writeln();
        writeln("*********************** Summary ***********************");
        writefln("Succeeded: %s", succeededToolchains.length);
        foreach (entry; succeededToolchains)
            writefln("    * %s", entry.toolchainID);
        writefln("Failed: %s", failedToolchains.length);
        foreach (entry; failedToolchains)
            writefln("    * %s", entry.toolchainID);

        return failedToolchains.empty;
    }

    /**
     * Build a single toolchain.
     */
    void build(Toolchain toolchain)
    {
        try
        {
            Toolchain[] dependencies;
            foreach (id; toolchain.builder.calculateDependencies())
            {
                enforce(id in _buildCache, format("Internal error: Dependency %s not built"));
                enforce(!_buildCache[id].failed, format("Dependency %s failed to build",
                    id));
                dependencies ~= _buildCache[id];
            }

            try
            {
                tryMkdir(toolchain.resultPath);
                tryRemove(configuration.tmpFolder);
                tryMkdir(configuration.tmpFolder);
                writeln(": Initializing build");
                toolchain.builder.initilize();
                writeln(": Installing dependencies");
                toolchain.builder.installDependencies(dependencies);
                writeln(": Starting backend build function");
                toolchain.builder.build();
                if (verbose)
                    writefln(": Result is at '%s'", toolchain.resultFile);
                if (!toolchain.dependencyOnly)
                {
                    import std.digest.md;

                    writeln(": Generating MD5 sum");
                    toolchain.md5Sum = File(toolchain.resultFile, "r").byChunk(8 * 1024).md5Of().toHexString!(
                        LetterCase.lower).idup;
                    if (verbose)
                        writefln(": MD5 is '%s'", toolchain.md5Sum);
                    auto resultFolder = configuration.resultFolder.buildPath(
                        toolchain.resultPath.relativePath(configuration.resultTMPFolder));
                    tryMkdir(resultFolder);
                    writefln(": Saving result to '%s'", resultFolder);
                    copyContents(toolchain.resultPath, resultFolder);
                }
            }
            catch (Exception e)
            {
                auto resultFolder = configuration.resultFolder.buildPath(
                    toolchain.resultPath.relativePath(configuration.resultTMPFolder));
                tryMkdir(resultFolder);
                copyContents(toolchain.resultPath, resultFolder);
                throw e;
            }
            finally
            {
                toolchain.builder.cleanup();
            }

        }
        catch (Exception e)
        {
            writefln(": Build failed: %s", e.toString());
            toolchain.failed = true;
        }
    }

    /**
     * Load build database.
     */
    void loadWebsiteGIT()
    {
        writeln(": Updating gdcproject");
        gdcb.util.chdir(configuration.websiteFolder);
        execute("git", "remote", "update");
        execute("git", "checkout", "origin/master");
    }

    /**
     * Initialize common folders
     */
    void initFolders()
    {
        if (!exists(configuration.tmpFolder))
            mkdirRecurse(configuration.tmpFolder);
        if (!exists(configuration.resultTMPFolder))
            mkdirRecurse(configuration.resultTMPFolder);
        if (!exists(configuration.sharedFolder))
            mkdirRecurse(configuration.sharedFolder);
        if (!exists(configuration.resultFolder))
            mkdirRecurse(configuration.resultFolder);

    }

public:
    bool initDL = false;
    bool initDB = false;
    bool verbose = false;
    uint keepAlive = 0;

    this()
    {
        import gdcb.backend.ctng;

        _backends ~= new CTNGBackend();
        _backends ~= new ArmEmbeddedBackend();
        _backends ~= new DKProBackend();
        initFolders();
    }

    /**
     * Build toolchains from ids.
     * 
     * Returns:
     *     true if all toolchains were built. false if one or more toolchains failed to build.
     * 
     * Throws:
     *     All kinds of exceptions on fatal errors.
     */
    bool buildToolchains(string[] ids, GitID[GCCVersion] sourceInfo = null,
        GitID configID = GitID("origin/master"))
    {
        Tid keepAliveTid;
        if (keepAlive != 0)
        {
            auto interval = dur!"seconds"(keepAlive);
            writeln("Starting thread to periodically print to stdout every %s", interval);
            keepAliveTid = spawn(&keepAliveThread, interval);
        }
        scope (exit)
        {
            if (keepAlive != 0)
            {
                send(keepAliveTid, true);
            }
        }

        loadWebsiteGIT();
        website = new DownloadSite();
        if (!initDL)
            website.loadDownloadList(configuration.websiteFolder.buildPath("views",
                "downloads.json"));
        if (!initDB)
            website.loadDatabase(configuration.websiteFolder.buildPath("views", "database.json"));

        if (!(GCCVersion.snapshot in sourceInfo))
            sourceInfo[GCCVersion.snapshot] = GitID("origin/master");
        if (!(GCCVersion.V4_7 in sourceInfo))
            sourceInfo[GCCVersion.V4_7] = GitID("origin/gdc-4.7");
        if (!(GCCVersion.V4_8 in sourceInfo))
            sourceInfo[GCCVersion.V4_8] = GitID("origin/gdc-4.8");
        if (!(GCCVersion.V4_9 in sourceInfo))
            sourceInfo[GCCVersion.V4_9] = GitID("origin/gdc-4.9");
        if (!(GCCVersion.V5 in sourceInfo))
            sourceInfo[GCCVersion.V5] = GitID("origin/gdc-5");

        updateGDMD();
        updateGDC();
        updateConfigs();
        checkoutConfigs(configID);

        writeln("Initializing backends");
        foreach (backend; _backends)
        {
            writeln("    * ", backend.getType());
            backend.initialize(sourceInfo, verbose);
        }

        writeln("Loading toolchain information");
        foreach (id; ids)
        {
            writeln("    * ", id);
            auto toolchain = Toolchain.load(id, true);
            setBuilder(toolchain);
            _target ~= toolchain;
        }

        auto result = build();

        writeln("Writing website information");

        website.saveDownloadList(configuration.resultDLFile);
        website.saveDatabase(configuration.resultDBFile);
        website.saveBuilds(configuration.resultBuildFile);

        return result;
    }
}

void keepAliveThread(Duration interval)
{
    bool keepRunning = true;
    while (keepRunning)
    {
        writeln("\n.");
        stdout.flush();
        receiveTimeout(interval, (bool b) {
            writeln("Exiting keepAlive thread.");
            keepRunning = false;
        },);
    }
}

enum GCCVersion
{
    snapshot,
    V4_7,
    V4_8,
    V4_9,
    V5
}

struct GitID
{
    string value;
}

class Toolchain
{
    /**
     * Only required as a dependency, don't save results.
     */
    bool dependencyOnly = false;

    /**
     * Attempted to build but failed.
     */
    bool failed = false;

    /**
     * Set by builder. If set, the toolchain will get it's own section on 
     * the download page.
     */
    string specialToolchainName = "";

    /**
     * Key-Value pairs used for the download page for special toolchains.
     */
    string[string] downloadInfo;

    /**
     * The toolchain id is the path relative to the configs folder.
     */
    string toolchainID;

    /**
     * Json toolchain configuration.
     */
    ToolchainConfig config;

    /**
     * Information about the used source.
     */
    SourceInfo source;

    /**
     * Builder used to build this toolchain.
     */
    BuildInstance builder;

    /**
     * Set by builder.
     */
    string filename;

    /**
     * MD5 sum of generated archive
     */
    string md5Sum;

    this(ToolchainConfig config_, bool dependency = false)
    {
        this.config = config_;
        this.dependencyOnly = dependency;
        this.toolchainID = config.path.relativePath(configuration.configFolder);
    }

    /**
     * Base path where backend should copy files to keep.
     */
    @property string resultPath()
    {
        return buildPath(configuration.resultTMPFolder,
            config.path.relativePath(configuration.configFolder));
    }

    /**
     * Filename where backend generated the final toolchain tarball.
     */
    @property string resultFile()
    {
        return buildPath(configuration.resultTMPFolder, resultFilePart);
    }

    /**
     * Filename relative to result dir.
     */
    @property string resultFilePart()
    {
        return buildPath(config.path.relativePath(configuration.configFolder), filename);
    }

    static Toolchain load(string id, bool dependency = false)
    {
        auto parts = findSplit(id, dirSeparator);
        return Toolchain.load(parts[0], parts[2], dependency);
    }

    static Toolchain load(string host, string tag, bool dependency = false)
    {
        auto hostDir = configuration.configFolder.buildPath(host);
        auto hostFile = hostDir.buildPath("host.json");
        auto toolChainDir = hostDir.buildPath(tag);
        auto toolchainFile = toolChainDir.buildPath("config.json");

        if (!hostDir.exists || !hostDir.isDir)
            throw new Exception(format("Couldn't find host directory %s", hostDir));
        if (!hostFile.exists || !hostFile.isFile)
            throw new Exception(format("Couldn't find host.json in %s", hostDir));
        if (!toolChainDir.exists || !toolChainDir.isDir)
            throw new Exception(format("Couldn't find toolchain directory %s", toolChainDir));
        if (!toolchainFile.exists || !toolchainFile.isFile)
            throw new Exception(format("Couldn't find config.json in %s", toolchainFile));

        HostInfo hostinfo;
        hostinfo.deserializeJson(readText(hostFile).parseJsonString());
        hostinfo.triplet = hostDir.baseName();
        hostinfo.path = hostDir;

        ToolchainConfig config;
        config.deserializeJson(readText(toolchainFile).parseJsonString());
        config.path = absolutePath(toolChainDir);
        config.host = hostinfo;

        return new Toolchain(config, dependency);
    }

    override string toString()
    {
        return toolchainID;
    }
}
