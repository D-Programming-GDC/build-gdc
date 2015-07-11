module gdcb.website;

import std.algorithm, std.array, std.exception, std.array, std.stdio, std.file;
import vibe.data.json;
import gdcb.config, gdcb.builder;

class DownloadJSON
{
    string[] multilib;
    string target, dmdFE, runtime, gcc, gdcRev, buildDate, url, comment, runtimeLink;
    string srcID, buildID, filename;
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
    bool oneBuildOnly;

    HostJSON[] hosts;

    /**
     * Load a .json file containing a list of downloads for
     * gdcproject.org
     */
    this(string path)
    {
        auto content = readText(path);
        deserializeJson(hosts, parseJsonString(content));
    }

    this()
    {
    }

    /**
     * Add a toolchain. Replaces older builds
     */
    void addToolchain(Toolchain toolchain)
    {
        // Use existing host if possible, otherwise create new
        auto hostRange = hosts.find!"a.triplet == b"(toolchain.config.host.triplet);
        HostJSON host;
        if (hostRange.empty)
        {
            host = new HostJSON();
            host.name = toolchain.config.host.name;
            host.triplet = toolchain.config.host.triplet;
            host.archiveURL = toolchain.config.host.archiveURL;
            host.comment = toolchain.config.host.comment;
            hosts ~= host;
        }
        else
        {
            host = hostRange.front;
        }

        // Use existing set if possible, otherwise create new
        auto setRange = host.sets.find!"a.id == b"(toolchain.config.set);
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
            host.sets ~= set;
        }
        else
        {
            set = setRange.front;
        }

        //If toolchain with id exists, remove
        if (oneBuildOnly)
            set.downloads = set.downloads.remove!(a => a.buildID == toolchain.config.buildID)();
        else
            set.downloads = set.downloads.remove!(a => a.srcID == toolchain.toolchainID)();

        //now add toolchain
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
        download.url = format("http://gdcproject.org/downloads/binaries/%s/%s",
            toolchain.config.host.triplet, toolchain.filename);
        download.comment = toolchain.config.comment;
        download.runtimeLink = toolchain.config.runtimeLink;
        download.multilib = toolchain.config.multilib;

        set.downloads ~= download;
    }

    void writeJSON(string path)
    {
        File file = File(path, "w");
        file.rawWrite(serializeToJson(hosts).toPrettyString());
        file.close();
    }
}
