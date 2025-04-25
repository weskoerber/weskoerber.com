+++
title = "Writing better CLI applications"
date = "2025-04-25"
+++

As programmers, we interact with command line utilities on a daily basis. These
days there are so many libraries for creating great utilities from TUIs to
simple argument parsers. It also helps that the POSIX and GNU standards for
command line arguments is damn near ubiquitous - hell, [even Microsoft adopted
them](https://learn.microsoft.com/en-us/dotnet/standard/commandline/syntax)
[^1]. However, I find that command line utilities are lacking in some areas. In
this post, I'll explore some areas I think need improvement, and suggest some
alternatives.

# Pipelines

[Pipelines](https://en.wikipedia.org/wiki/Pipeline_(Unix)) are used heavily in
Unix-like operating systems, and is often what makes it stand out. Instead of
creating large, clunky, and complicated applications that try to implement every
feature the authors can think of, the philosophy of Unix is to implement the
most basic functionality, and use other programs to perform some further
operations.

When running command line applications, the output of the application is
typically formatted in a way that makes it easily readable by humans. This
usually takes the form of a table, grid, or list. This is great for us humans,
as it's easy for our brains to read and interpret at a quick glance. But that's
not easiest for a machine to parse [^2]. Sure, there's many great utilities like
`awk`, `sed`, and `grep`, but I think there's a better way.

When a command-line application runs, it could detect whether its `stdout` is a
terminal device or some other handle. For example, `stdout` could be connected
to `stdin` of another program, in which case it would be a pipe. Applications
could detect this and determine the output format to use.

Every application has its own way of outputting data. Look at the `lsblk` and
`ls` commands. They're both tabular data, but you would need to implement
parsing logic twice - once for each command. If you have to run many commands,
having individual parsing logic for each becomes time-consuming and clutters the
actual purpose of your application. Instead, applications should be able to
output data in a format that other utilities can accept easily that minimizes
the effort required to extract data.

For example, if the application's `stdout` is a terminal, it could output its
results in a tabular format. But when `stdout` is a pipe, maybe it could output
its results in some sort of structured text format, such as JSON. This would
enable the use of `jq` to parse the output easily. Or maybe you can send the
JSON data to some other environment. Since most languages have libraries that
can parse JSON, integration is trivial.

There should still be options for overriding this behavior though, since one
use-case could be piping results to a pager to view and navigate a high volume
of output more easily. In this case, since the application's `stdout` is a pipe
connected to the pager's `stdin`, the application would output JSON, but we want
the tabular format. Here we could explicitly tell the application we want the
tabular output style with an option, such as `--output-style=tabular`.

# The client -> server model

In the world of Unix-like operating systems, a pattern you'll see implemented
often for applications is to have a daemon process which implements the
application's business logic and listens for input via IPC (socket, pipe, shared
memory, etc), and a small command-line utility that talks to the daemon process
over this IPC channel. There are many utilities that use this pattern:
- makoctl -> mako ([repo](https://github.com/emersion/mako))
- nmcli -> NetworkManager ([repo](https://gitlab.freedesktop.org/NetworkManager/NetworkManager))
- swaymsg -> sway ([repo](https://github.com/swaywm/sway))
- wpctl -> wireplumber ([repo](https://gitlab.freedesktop.org/pipewire/wireplumber/))
- Most of systemd, such as:
    - journalctl -> systemd-journald
    - loginctl -> systemd-logind
    - networkctl -> systemd-networkd

I think this pattern works really well, because it separates the actual logic of
the application and the user interface. It also works really well cross-platform
too, particularly on Windows, since services are a special type of application
that is non-interactive. It also simplifies environments where you may have
multiple users. You only need one daemon process, but you are able to have many
client processes talking to the daemon over the IPC channel. Several other
aspects of the application are easier to control and manages, such as access
control, daemon lifetime management, logging, etc.

Of course, this is just not the right pattern for some applications. For
example, the `ls` command doesn't need to be this complex. A much more
appropriate invocation strategy is the one-shot method (the way it's currently
implemented), where the application launches, it processes its input, does some
stuff, then exits.

# Exit codes and error messages

Most of the time, when applications quit due to an error, the error code is 1.
However, there may be many reasons for an application to terminate unexpectedly.
How is a user supposed to differentiate between different conditions not being
met, errors with input, etc? For example, if a program terminates because a file
doesn't exist, how can the user of the application differentiate that between
termination due to an invalid option? In my opinion, each error code should
correspond to a particular condition. I really don't like the idea of "unknown"
or "generic" errors. Most of the time, these errors are not "unknown" or
"generic", the author is just too lazy to specifically identify them. Error
messages typically take the burden of identifying specific errors by emitting a
message to `stderr`. This isn't easy for applications to parse, since the error
messages are often formatted with some input from the user.

Error messages in another area that can be improved. Applications such as code
compilers have pretty good error messages. The messages are good enough that
they often tell you the exact source of the problematic line, and sometimes even
the problematic character (such as a missing semi-colon). Rust is the gold
standard for compiler errors. We should take a page out of its book and apply it
to our command line applications.

# Man pages

This one is subjective, but I *love* man pages. Finding help in a man page is so
much quicker than googling, and you don't have to search several links to find
what you need. Just `man my_application` and you have everything you need to
know. Applications commonly give you man pages for the usage and purpose of the
application. I really like when applications provide man pages for configuration
files (e.g. `man 5 gitignore`). I think more applications should do this.

[^1]: Just to be clear, POSIX doesn't strictly define long options (i.e.
`--option=value`, `--option value`, or `--option`), but long options are not
inherently incompatible with POSIX-compliant systems.

[^2]: What I mean here really is that it's not the easiest to write utilities
that parse the output. Optimal machine parsing would be binary data, not
text streams.
