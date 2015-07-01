module gdcb.website;
import std.stdio;
import vibe.data.json;

import gdcb.database, gdcb.config;

import std.algorithm, std.exception, std.array;

struct DownloadJSON
{
    string[] multilib;
    string target, dmdFE, runtime, gcc, gdcRev, buildDate, url, comment, runtimeLink;
}

struct DownloadSetJSON
{
    string name, comment, targetHeader;
    DownloadJSON[] downloads;
}

struct HostJSON
{
    string name, triplet, archiveURL, comment;
    DownloadSetJSON[] sets;
}

struct DownloadSite
{
    private DownloadDB _db;

    this(DownloadDB db)
    {
        _db = db;
    }

    void writeJSON(string path)
    {
        HostJSON[] hosts;
        foreach (host; _db.getHosts())
        {
            HostJSON hostJS;
            hostJS.name = host.name;
            hostJS.triplet = host.triplet;
            hostJS.archiveURL = host.archiveURL;
            hostJS.comment = host.comment;
            foreach (dlSet; _db.getSets(host.id))
            {
                DownloadSetJSON setJS;
                setJS.name = dlSet.name;
                setJS.comment = dlSet.comment;
                setJS.targetHeader = dlSet.targetHeader;

                auto targets = _db.getTargetsForSet(dlSet.id);
                foreach (tnum, target; targets)
                {
                    auto feVers = _db.getFEVers(dlSet.id, target);
                    feVers = sort!"a > b"(feVers).array();

                    void addDL(string feVer)
                    {
                        DownloadJSON dlJS;
                        auto downloads = _db.getDownloads(dlSet.id, target, feVer);
                        downloads = sort!"a.buildDate > b.buildDate"(downloads).array();
                        auto dl = downloads[0];

                        dlJS.target = dl.target;
                        dlJS.dmdFE = dl.dmdFE;
                        dlJS.runtime = dl.runtime;
                        dlJS.gcc = dl.gcc;
                        dlJS.gdcRev = dl.gdcRev[0 .. 10];
                        dlJS.buildDate = dl.buildDate;
                        dlJS.url = dl.url;
                        dlJS.comment = dl.comment;
                        dlJS.runtimeLink = dl.runtimeLink;
                        dlJS.multilib = dl.multilib;
                        setJS.downloads ~= dlJS;
                    }

                    //FIXME: Add some way to ignore outdated downloads
                    if (target != "native")
                        addDL(feVers[0]);
                }
                hostJS.sets ~= setJS;
            }
            hosts ~= hostJS;
        }

        File file = File(path, "w");
        file.rawWrite(serializeToJson(hosts).toPrettyString());
        file.close();
    }
}
