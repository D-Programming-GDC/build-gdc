module gdcb.website;

import std.algorithm, std.array, std.exception, std.array, std.stdio, std.file,
    std.range;
import vibe.data.json;
import gdcb.config, gdcb.builder;

class DownloadJSON
{
    string[] multilib;
    string target, dmdFE, runtime, gcc, gdcRev, buildDate, url, comment, runtimeLink;
    string srcID, buildID, filename, md5Sum;
    uint release;
}

class DownloadSetJSON
{
    string name, comment, targetHeader, id;
    DownloadJSON[] downloads;
}

class HostJSON
{
    string name, triplet, archiveURL, comment;
    DownloadSetJSON[] sets;
}

class DownloadSite
{
private:
    string getDownloadURL(Toolchain toolchain)
    {
        import std.algorithm : endsWith;

        if (toolchain.config.backend != "ctng")
        {
            return format("http://gdcproject.org/downloads/binaries/%s/%s/%s",
                toolchain.source.gccVersion, toolchain.config.host.triplet, toolchain.filename);
        }

        string extension;
        if (toolchain.filename.endsWith(".tar.xz"))
            extension = "tar.xz";
        else if (toolchain.filename.endsWith(".7z"))
            extension = "7z";
        else
            throw new Exception("Invalid extension in filname: " ~ toolchain.filename);

        if (toolchain.config.host.triplet == toolchain.config.target)
        {
            // /binaries/4.8.4/x86_64-linux-gnu/gdc-4.8.4+2.061.2.tar.xz
            return format("http://gdcproject.org/downloads/binaries/%s/%s/gdc-%s+%s.%s",
                toolchain.source.gccVersion, toolchain.config.host.triplet,
                toolchain.source.gccVersion, toolchain.source.dmdFE, extension);
        }
        else
        {
            // /binaries/4.8.4/x86_64-linux-gnu/gdc-4.8.4-arm-linux-gnueabi+2.061.2.tar.xz
            return format("http://gdcproject.org/downloads/binaries/%s/%s/gdc-%s-%s+%s.%s",
                toolchain.source.gccVersion, toolchain.config.host.triplet,
                toolchain.source.gccVersion, toolchain.config.target,
                toolchain.source.dmdFE, extension);
        }
    }

    /// Use existing host if possible, otherwise create new
    HostJSON getHost(ref HostJSON[] root, Toolchain toolchain)
    {
        auto hostRange = root.find!"a.triplet == b"(toolchain.config.host.triplet);
        HostJSON host;
        if (hostRange.empty)
        {
            host = new HostJSON();
            host.name = toolchain.config.host.name;
            host.triplet = toolchain.config.host.triplet;
            host.archiveURL = toolchain.config.host.archiveURL;
            host.comment = toolchain.config.host.comment;
            root ~= host;
        }
        else
        {
            host = hostRange.front;
        }

        return host;
    }

    /// Use existing set if possible, otherwise create new
    DownloadSetJSON getSet(ref DownloadSetJSON[] root, Toolchain toolchain)
    {
        auto setRange = root.find!"a.id == b"(toolchain.config.set);
        DownloadSetJSON set;
        if (setRange.empty)
        {
            set = new DownloadSetJSON();
            auto configset = toolchain.config.host.downloadSets.find!"a.id == b"(
                toolchain.config.set);
            enforce(!configset.empty, "Unknown download set " ~ toolchain.config.set);

            set.targetHeader = configset.front.targetHeader;
            set.name = configset.front.name;
            set.comment = configset.front.comment;
            set.id = configset.front.id;
            root ~= set;
        }
        else
        {
            set = setRange.front;
        }

        return set;
    }

    DownloadJSON getDownload(Toolchain toolchain)
    {
        auto download = new DownloadJSON();

        download.filename = toolchain.filename;
        download.srcID = toolchain.toolchainID;
        download.buildID = toolchain.config.buildID;
        download.target = toolchain.config.target;
        download.dmdFE = toolchain.source.dmdFE;
        download.runtime = toolchain.config.runtime;
        download.gcc = toolchain.source.gccVersion;
        download.gdcRev = toolchain.source.gdcRevision;
        download.buildDate = format("%04d-%02d-%02d",
            toolchain.source.date.year, toolchain.source.date.month, toolchain.source.date.day);
        download.url = "";
        download.comment = toolchain.config.comment;
        download.runtimeLink = toolchain.config.runtimeLink;
        download.multilib = toolchain.config.multilib;
        download.md5Sum = toolchain.md5Sum;

        return download;
    }

    void addToDownload(Toolchain toolchain, uint num)
    {
        HostJSON host = getHost(dlHosts, toolchain);
        DownloadSetJSON set = getSet(host.sets, toolchain);

        // We only keep one build with same buildID in download list
        set.downloads = set.downloads.remove!(a => a.buildID == toolchain.config.buildID)();

        auto download = getDownload(toolchain);
        download.url = getDownloadURL(toolchain);
        download.release = num;
        set.downloads ~= download;
    }

    // Returns release number
    uint addToDatabase(Toolchain toolchain)
    {
        HostJSON host = getHost(dbHosts, toolchain);
        DownloadSetJSON set = getSet(host.sets, toolchain);

        auto download = getDownload(toolchain);
        auto url = getDownloadURL(toolchain);
        uint release = cast(uint)(set.downloads.filter!(a => a.url == url).walkLength()) + 1;
        download.url = url;
        download.release = release;
        set.downloads ~= download;

        return release;
    }

    void addToBuilds(Toolchain toolchain)
    {
        HostJSON host = getHost(builtHosts, toolchain);
        DownloadSetJSON set = getSet(host.sets, toolchain);

        set.downloads ~= getDownload(toolchain);
    }

public:
    // downloads.json
    HostJSON[] dlHosts;

    // database.json
    HostJSON[] dbHosts;

    // built-toolchains.json
    HostJSON[] builtHosts;

    this()
    {
    }

    /**
     * Load a .json file containing a list of active downloads for
     * gdcproject.org
     */
    void loadDownloadList(string path)
    {
        auto content = readText(path);
        deserializeJson(dlHosts, parseJsonString(content));
    }

    /**
     * Load a .json file containing a list of all builds at
     * gdcproject.org
     */
    void loadDatabase(string path)
    {
        auto content = readText(path);
        deserializeJson(dbHosts, parseJsonString(content));
    }

    void saveDownloadList(string path)
    {
        File file = File(path, "w");
        file.rawWrite(serializeToJson(dlHosts).toPrettyString());
        file.close();
    }

    void saveDatabase(string path)
    {
        File file = File(path, "w");
        file.rawWrite(serializeToJson(dbHosts).toPrettyString());
        file.close();
    }

    void saveBuilds(string path)
    {
        File file = File(path, "w");
        file.rawWrite(serializeToJson(builtHosts).toPrettyString());
        file.close();
    }

    /**
     * Add a toolchain. Replaces older builds
     */
    void addToolchain(Toolchain toolchain)
    {
        addToBuilds(toolchain);

        auto num = addToDatabase(toolchain);
        addToDownload(toolchain, num);
    }
}
