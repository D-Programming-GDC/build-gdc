module gdcb.util;

import std.file, std.string, std.process, std.stdio, std.exception;
import core.stdc.stdlib;

private void logError(string msg)
{
    writeln(msg);
    throw new Exception(msg);
}

private void removeHelper(string path)
{
    if (path.isFile)
        std.file.remove(path);
    else if (path.isDir)
        std.file.rmdirRecurse(path);
    else
        logError(format("Cannot delete %s: Neither file nor directory", path));
}

void execute(string[] args...)
{
    execute(true, null, args);
}

void execute(bool log, string[] args...)
{
    execute(log, null, args);
}

void execute(string[string] env, string[] args...)
{
    execute(true, env, args);
}

void execute(bool log, string[string] env, string[] args...)
{
    if (args.length > 1)
        writefln("Execute: %s %s", args[0], args[1 .. $]);
    else
        writefln("Execute: %s", args[0]);

    auto pipes = pipeProcess(args, Redirect.stdout | Redirect.stderrToStdout, env);
    foreach (line; pipes.stdout.byLine())
    {
        if (log)
            writefln("    %s", line);
    }
    if (!log)
        writefln("    (suppressed output)");
    auto result = wait(pipes.pid);

    if (result != EXIT_SUCCESS)
        logError(format("Error: Executing %s failed", args[0]));
}

void executeShell(string cmd)
{
    writefln("Execute: %s", cmd);
    std.process.executeShell(cmd);
}

void remove(string path)
{
    writefln("Deleting %s", path);
    checkExists(path);
    removeHelper(path);
}

void tryRemove(string path)
{
    if (!path.exists)
    {
        return;
    }
    writefln("Deleting %s", path);
    removeHelper(path);
}

void tryMkdir(string path)
{
    if (path.exists)
        writefln("Not creating directory %s (exists)", path);
    else
        mkdir(path);
}

void mkdir(string path)
{
    writefln("Creating directory %s", path);
    if (path.exists)
        logError(format("Error: %s does already exists", path));

    std.file.mkdirRecurse(path);
}

void chdir(string path)
{
    writefln("Entering directory %s", path);
    checkExists(path);
    std.file.chdir(path);
}

void checkExists(string path)
{
    if (!path.exists)
        logError(format("Error: %s does not exist", path));
}

void moveFile(string src, string dst)
{
    writefln("Move file %s --> %s", src, dst);
    checkExists(src);
    if (!src.isFile)
        logError(format("Error: %s is not a file", src));
    if (dst.exists)
        logError(format("Error: %s already exists", dst));

    copy(src, dst);
    std.file.remove(src);
}

/**
 * FIXME: Shallow copy!
 */
void copyContents(string src, string dst)
{
    import std.path;

    writefln("Copying %s/* --> %s/*", src, dst);
    checkExists(src);
    checkExists(dst);
    foreach (entry; dirEntries(src, SpanMode.shallow))
    {
        if (entry.isFile)
            copy(entry, dst.buildPath(relativePath(entry, src)));
    }
}

version (Posix)
{
    import core.sys.posix.sys.stat;

    void chmod(string path, mode_t mode)
    {
        checkExists(path);
        writefln("chmod %o %s", mode, path);
        errnoEnforce(core.sys.posix.sys.stat.chmod(path.toStringz(), mode) == 0);
    }
}
