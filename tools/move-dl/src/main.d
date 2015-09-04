import vibe.data.json, std.file, std.stdio, std.path;

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

void main(string[] args)
{
    HostJSON[] root;
    auto content = readText(args[1]);
    deserializeJson(root, parseJsonString(content));
    string leadingURL = "http://gdcproject.org/downloads/binaries/";
    string destRoot = "/srv/gdcproject/site/downloads/binaries";

    foreach (host; root)
    {
        foreach (set; host.sets)
        {
            foreach (dl; set.downloads)
            {
                string filePath = dl.url[leadingURL.length .. $];
                string fileDir = dirName(filePath);
                writefln("sudo -u gdcproject mkdir -p %s/%s", destRoot, fileDir);
                writefln("sudo -u gdcproject cp -v %s/%s %s/%s", dl.srcID,
                    dl.filename, destRoot, filePath);
            }
        }
    }
}
