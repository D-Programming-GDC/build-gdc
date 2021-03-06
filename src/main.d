module main;

import core.stdc.stdlib, std.getopt, std.stdio;
import gdcb.builder;

int main(string[] args)
{
    string command;
    if (args.length < 2)
    {
        writeln("Usage: builder command [options]");
        return EXIT_SUCCESS;
    }
    else
    {
        command = args[1];
        args = args[1 .. $];
    }

    bool help = false;
    switch (command)
    {
    case "--help":
        printGenericHelp();
        return EXIT_SUCCESS;
    case "build":
        bool initDB, initDL, verbose;
        string[] toolchains;
        string toolchainList;
        GitID[GCCVersion] revs;
        string configRev = "origin/master";
        uint keepAlive = 0;

        void handleRev(string option, string value)
        {
            import std.algorithm, std.conv;

            auto parts = value.findSplit(":");
            auto ver = to!GCCVersion(parts[0]);
            revs[ver] = GitID(parts[2]);
        }

        getopt(args, config.noPassThrough, "help", &help, "toolchain",
            &toolchains, "init-downloads", &initDL, "init-database", &initDB,
            "toolchain-list", &toolchainList, "verbose", &verbose,
            "revision", &handleRev, "config-revision", &configRev, "keep-alive", &keepAlive);

        if (help)
            writeln(
                "Usage: build-gdc build [--verbose] [--toolchain='id'] [--toolchain-list='path']" ~ "\n\t [--init-database] [--init-downloads] [--revision=GCCVersion:rev] [--config-revision=rev]" ~ "\n\t [--keep-alive=N]");
        else
        {
            auto builder = new Builder();
            builder.initDB = initDB;
            builder.initDL = initDL;
            builder.verbose = verbose;
            builder.keepAlive = keepAlive;

            if (toolchainList.length != 0)
            {
                import vibe.data.json, std.file, std.path, gdcb.config;

                if (!exists(toolchainList))
                {
                    auto newPath = configuration.listFolder.buildPath(toolchainList);
                    auto newPath2 = configuration.listFolder.buildPath(toolchainList ~ ".json");
                    if (exists(newPath))
                        toolchainList = newPath;
                    else if (exists(newPath2))
                        toolchainList = newPath2;
                    else
                        throw new Exception("--toolchain-list file not found!");

                }
                string[] toolchainEntries;
                string json = readText(toolchainList);
                toolchainEntries.deserializeJson(parseJson(json));
                return builder.buildToolchains(toolchainEntries, revs, GitID(configRev)) ? EXIT_SUCCESS
                    : EXIT_FAILURE;
            }
            else if (toolchains.length != 0)
            {
                return builder.buildToolchains(toolchains, revs, GitID(configRev)) ? EXIT_SUCCESS
                    : EXIT_FAILURE;
            }
        }
        break;
    default:
        writefln("Error: Unknown command %s", command);
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}

void printGenericHelp()
{
    writeln("Usage: build-gdc command [options]");
    writeln();
    writeln("Available commands:");
    writeln("\tbuild                Build toolchains");
}
