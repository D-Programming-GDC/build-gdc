module gdcb.database;

import std.file;
import gdcb.config;
import d2sqlite3;
import sqlite3 : sqlite3_last_insert_rowid;

struct Host
{
    long id = -1;
    string name, triplet, archiveURL;
    string comment;

    @property bool empty()
    {
        return id == -1;
    }

    static Host fromRow(Row row)
    {
        Host h;
        h.id = row["id"].as!long();
        h.name = row["name"].as!string();
        h.triplet = row["triplet"].as!string();
        h.archiveURL = row["archiveURL"].as!string();
        h.comment = row["comment"].as!string();
        return h;
    }
}

struct DownloadSet
{
    long id = -1;
    string name, idString;
    string comment;
    string targetHeader;
    long hostID;

    @property bool empty()
    {
        return id == -1;
    }

    static DownloadSet fromRow(Row row)
    {
        DownloadSet d;
        d.id = row["id"].as!long();
        d.name = row["name"].as!string();
        d.idString = row["idString"].as!string();
        d.comment = row["comment"].as!string();
        d.targetHeader = row["targetHeader"].as!string();
        d.hostID = row["hostID"].as!long();
        return d;
    }
}

struct Download
{
    long id = -1;
    long setID, hostID;
    private string _multilibRaw;
    string target, dmdFE, runtime, gcc, gdcRev, buildDate, url;
    string comment, runtimeLink;
    string filepath;

    @property string[] multilib()
    {
        import std.array;

        return split(_multilibRaw, ",");
    }

    @property void multilib(string[] value)
    {
        import std.array;

        _multilibRaw = join(value, ",");
    }

    @property bool empty()
    {
        return id == -1;
    }

    static Download fromRow(Row row)
    {
        Download d;
        d.id = row["id"].as!long();
        d.target = row["target"].as!string();
        d.dmdFE = row["dmdFE"].as!string();
        d.runtime = row["runtime"].as!string();
        d.gcc = row["gcc"].as!string();
        d.gdcRev = row["gdcRev"].as!string();
        d.buildDate = row["buildDate"].as!string();
        d.url = row["url"].as!string();
        d.filepath = row["filepath"].as!string();
        d.comment = row["comment"].as!string();
        d.runtimeLink = row["runtimeLink"].as!string();
        d._multilibRaw = row["multilib"].as!string();
        d.setID = row["setID"].as!long();
        d.hostID = row["hostID"].as!long();
        return d;
    }
}

class DownloadDB
{
private:
    Database _db;
    string _dbPath;

    void open()
    {
        _db = Database(_dbPath);
    }

    void createTables()
    {
        _db = Database(_dbPath);
        _db.execute("CREATE TABLE IF NOT EXISTS Hosts (
            id INTEGER PRIMARY KEY,
            triplet TEXT NOT NULL,
            name TEXT,
            archiveURL TEXT,
            comment TEXT
            )");
        _db.execute("CREATE TABLE IF NOT EXISTS DownloadSets (
            id INTEGER PRIMARY KEY,
            idString TEXT,
            name TEXT NOT NULL,
            comment TEXT,
            targetHeader TEXT,
            hostID INTEGER
            )");
        _db.execute("CREATE TABLE IF NOT EXISTS Downloads (
            id INTEGER PRIMARY KEY,
            target TEXT NOT NULL,
            dmdFE TEXT,
            runtime TEXT,
            gcc TEXT,
            gdcRev TEXT,
            buildDate TEXT,
            url TEXT,
            filepath TEXT,
            comment TEXT,
            runtimeLink TEXT,
            multilib TEXT,
            setID INTEGER,
            hostID INTEGER
            )");
    }

public:
    this(string path)
    {
        _dbPath = path;
        open();
        createTables();
    }

    void beginTransaction()
    {
        _db.execute("BEGIN TRANSACTION");
    }

    void endTransaction()
    {
        _db.execute("END TRANSACTION");
    }

    Host getHost(long id)
    {
        auto query = _db.prepare("SELECT * FROM Hosts WHERE id == :id");
        query.bind(":id", id);
        auto range = query.execute();
        if (range.empty)
            return Host.init;
        else
            return Host.fromRow(range.front);
    }

    Host getHost(string triplet)
    {
        auto query = _db.prepare("SELECT * FROM Hosts WHERE triplet == :triplet");
        query.bind(":triplet", triplet);
        auto range = query.execute();
        if (range.empty)
            return Host.init;
        else
            return Host.fromRow(range.front);
    }

    Host[] getHosts()
    {
        Host[] result;
        auto query = _db.prepare("SELECT * FROM Hosts");
        auto range = query.execute();
        foreach (row; range)
            result ~= Host.fromRow(row);
        return result;
    }

    long addHost(Host h)
    {
        assert(h.empty);
        auto query = _db.prepare("INSERT INTO Hosts (name, triplet, archiveURL, comment)
             VALUES (:name, :triplet, :archiveURL, :comment)");

        query.bind(":name", h.name);
        query.bind(":triplet", h.triplet);
        query.bind(":archiveURL", h.archiveURL);
        query.bind(":comment", h.comment);
        query.execute();
        return sqlite3_last_insert_rowid(_db.handle);
    }

    void updateHost(Host h)
    {
        assert(!h.empty);
        auto query = _db.prepare(
            "UPDATE Hosts SET name=:name, triplet=:triplet, archiveURL=:archiveURL, comment=:comment
             WHERE id==:id");

        // Bind everything with chained calls to params.bind().
        query.bind(":id", h.id);
        query.bind(":name", h.name);
        query.bind(":triplet", h.triplet);
        query.bind(":archiveURL", h.archiveURL);
        query.bind(":comment", h.comment);
        query.execute();
    }

    Download[] getDownloads(long setID)
    {
        Download[] result;
        auto query = _db.prepare("SELECT * FROM Downloads WHERE setID == :setID");
        query.bind(":setID", setID);
        auto range = query.execute();
        foreach (row; range)
            result ~= Download.fromRow(row);
        return result;
    }

    Download[] getDownloads(long setID, string target)
    {
        Download[] result;
        auto query = _db.prepare(
            "SELECT * FROM Downloads WHERE setID == :setID AND target == :target");
        query.bind(":setID", setID);
        query.bind(":target", target);
        auto range = query.execute();
        foreach (row; range)
            result ~= Download.fromRow(row);
        return result;
    }

    Download[] getDownloads(long setID, string target, string dmdFE)
    {
        Download[] result;
        auto query = _db.prepare(
            "SELECT * FROM Downloads WHERE setID == :setID AND target == :target AND dmdFE == :dmdFE");
        query.bind(":setID", setID);
        query.bind(":target", target);
        query.bind(":dmdFE", dmdFE);
        auto range = query.execute();
        foreach (row; range)
            result ~= Download.fromRow(row);
        return result;
    }

    string[] getTargetsForSet(long setID)
    {
        string[] result;
        auto query = _db.prepare("SELECT DISTINCT target FROM Downloads WHERE setID == :setID");
        query.bind(":setID", setID);
        auto range = query.execute();
        foreach (row; range)
            result ~= row["target"].as!string();
        return result;
    }

    string[] getFEVers(long setID, string target)
    {
        string[] result;
        auto query = _db.prepare(
            "SELECT DISTINCT dmdFE FROM Downloads WHERE setID == :setID AND target == :target");
        query.bind(":setID", setID);
        query.bind(":target", target);
        auto range = query.execute();
        foreach (row; range)
            result ~= row["dmdFE"].as!string();
        return result;
    }

    Download getDownload(long id)
    {
        auto query = _db.prepare("SELECT * FROM Download WHERE id == :id");
        query.bind(":id", id);
        auto range = query.execute();
        if (range.empty)
            return Download.init;
        else
            return Download.fromRow(range.front);
    }

    long addDownload(Download d)
    {
        assert(d.empty);
        auto query = _db.prepare(
            "INSERT INTO Downloads (target, dmdFE, runtime, gcc, gdcRev, buildDate, url, filepath, comment,
             runtimeLink, multilib, setID, hostID)
             VALUES (:target, :dmdFE, :runtime, :gcc, :gdcRev, :buildDate, :url, :filepath, :comment,
             :runtimeLink, :multilib, :setID, :hostID)");

        // Bind everything with chained calls to params.bind().
        query.bind(":target", d.target);
        query.bind(":dmdFE", d.dmdFE);
        query.bind(":runtime", d.runtime);
        query.bind(":gcc", d.gcc);
        query.bind(":gdcRev", d.gdcRev);
        query.bind(":buildDate", d.buildDate);
        query.bind(":url", d.url);
        query.bind(":filepath", d.filepath);
        query.bind(":comment", d.comment);
        query.bind(":runtimeLink", d.runtimeLink);
        query.bind(":multilib", d._multilibRaw);
        query.bind(":setID", d.setID);
        query.bind(":hostID", d.hostID);
        query.execute();
        return sqlite3_last_insert_rowid(_db.handle);
    }

    void updateDownload(Download d)
    {
        assert(!d.empty);
        auto query = _db.prepare("UPDATE Downloads SET target=:target, dmdFE=:dmdFE, runtime=:runtime, gcc=:gcc, gdcRev=:gdcRev, buildDate=:buildDate,
             url=:url, filepath=:filepath, comment=:comment, runtimeLink=:runtimeLink, multilib=:multilib, setID=:setID, hostID=:hostID
             WHERE id==:id");

        // Bind everything with chained calls to params.bind().
        query.bind(":id", d.id);
        query.bind(":target", d.target);
        query.bind(":dmdFE", d.dmdFE);
        query.bind(":runtime", d.runtime);
        query.bind(":gcc", d.gcc);
        query.bind(":gdcRev", d.gdcRev);
        query.bind(":buildDate", d.buildDate);
        query.bind(":url", d.url);
        query.bind(":filepath", d.filepath);
        query.bind(":comment", d.comment);
        query.bind(":runtimeLink", d.runtimeLink);
        query.bind(":multilib", d._multilibRaw);
        query.bind(":setID", d.setID);
        query.bind(":hostID", d.hostID);
        query.execute();
    }

    DownloadSet[] getSets(long hostID)
    {
        DownloadSet[] result;
        auto query = _db.prepare("SELECT * FROM DownloadSets WHERE hostID == :hostID");
        query.bind(":hostID", hostID);
        auto range = query.execute();
        foreach (row; range)
            result ~= DownloadSet.fromRow(row);
        return result;
    }

    DownloadSet getSet(long id)
    {
        auto query = _db.prepare("SELECT * FROM DownloadSets WHERE id == :id");
        query.bind(":id", id);
        auto range = query.execute();
        if (range.empty)
            return DownloadSet.init;
        else
            return DownloadSet.fromRow(range.front);
    }

    DownloadSet getSet(long hostID, string setID)
    {
        auto query = _db.prepare(
            "SELECT * FROM DownloadSets WHERE idString == :setID AND hostID == :hostID");
        query.bind(":setID", setID);
        query.bind(":hostID", hostID);
        auto range = query.execute();
        if (range.empty)
            return DownloadSet.init;
        else
            return DownloadSet.fromRow(range.front);
    }

    long addSet(DownloadSet s)
    {
        assert(s.empty);
        auto query = _db.prepare(
            "INSERT INTO DownloadSets (name, idString, comment, targetHeader, hostID)
             VALUES (:name, :idString, :comment, :targetHeader, :hostID)");

        // Bind everything with chained calls to params.bind().
        query.bind(":name", s.name);
        query.bind(":idString", s.idString);
        query.bind(":comment", s.comment);
        query.bind(":targetHeader", s.targetHeader);
        query.bind(":hostID", s.hostID);
        query.execute();
        return sqlite3_last_insert_rowid(_db.handle);
    }

    void updateSet(DownloadSet s)
    {
        assert(!s.empty);
        auto query = _db.prepare("UPDATE DownloadSets SET name=:name, idString=:idString, comment0:comment, targetHeader=:targetHeader, hostID=:hostID
             WHERE id == :id");

        // Bind everything with chained calls to params.bind().
        query.bind(":id", s.id);
        query.bind(":name", s.name);
        query.bind(":idString", s.idString);
        query.bind(":comment", s.comment);
        query.bind(":targetHeader", s.targetHeader);
        query.bind(":hostID", s.hostID);
        query.execute();
    }

    void close()
    {
    }
}
