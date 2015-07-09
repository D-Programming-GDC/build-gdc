module gdcb.config;

import vibe.data.json;

struct Configuration
{
    string baseFolder = "/home/build";
    string configBaseFolder = "/home/build/build-gdc-config";
    string configFolder = "/home/build/build-gdc-config/configs";
    string listFolder = "/home/build/build-gdc-config/lists";
    string sourceDBFile = "/home/build/build-gdc-config/downloads.db";
    string tmpFolder = "/home/build/tmp";
    string sharedFolder = "/home/build/shared";
    string resultFolder = "/home/build/shared/result";
    string resultTMPFolder = "/home/build/result-tmp";
    string resultDBFile = "/home/build/shared/result/downloads.db";
    string resultJSONFile = "/home/build/shared/result/downloads.json";
    string gdcFolder = "/home/build/GDC";
    string websiteFolder = "/home/build/gdcproject";
}

Configuration configuration;

/**
 * Contents of configs/$HOST/.../config.json
 */
struct ToolchainConfig
{
    string target, runtime, set;
    @optional string comment;
    @optional string runtimeLink;
    @optional string[] multilib;
    @optional Json buildConfig;
    @optional string[] depends;
    string buildID;

    string ctTarget;
    string backend;

    @ignore string path;
    @ignore HostInfo host;
}

struct DownloadSet
{
    string name, id;
    @optional string comment;
    @optional string targetHeader = "Target";
}

/**
 * Contents of configs/$HOST/host.json
 */
struct HostInfo
{
    string name, archiveURL;
    @ignore string triplet;
    @optional string comment;
    DownloadSet[] downloadSets;

    @ignore string path;
}
