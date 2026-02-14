+++
title = "Securing .env files"
date = "2026-02-14"
+++

# Overview

Recently I've been toying around with a small homelab. I have an Intel NUC that
was gifted to me by a friend and have been running a suite of Docker containers.
I have a private [Gitea](https://about.gitea.com/) server where I can put shitty
code that I don't want anyone to see; I have [Actual
Budget](https://actualbudget.org/) running where I can track my finances (I
finally said "bye" to [YNAB](https://www.ynab.com/) after [yet another price
increase](https://www.reddit.com/r/ynab/comments/1ik8su5/ynab_pricing_history_2016_2025/)[^1]);
Pi-hole, where I can see just how many requests are spent on analytics, ads,
tracking, and other shit; and a couple others).

# Reverse Proxy

My homelab is not directly accessible from the internet. Instead, I have a
$11/year - yes, $11 **per year**[^2] [^3] - [RackNerd
VPS](https://my.racknerd.com/aff.php?aff=13788&pid=903) running
[Pangolin](https://pangolin.net/), [Crowdsec](https://www.crowdsec.net/), and
[Traefik](https://traefik.io/traefik). In my homelab, I run a
[Newt](https://docs.pangolin.net/manage/sites/install-site) container that makes
an outbound connection to Pangolin, which then make services available. Pangolin
also provides access control to secure access to these services. It's
essentially an open-source [Cloudflare
Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/).

# Deploying

I have a repository that contains all my services in [Docker
Compose](https://docs.docker.com/compose/) files. These services have `.env`
files that define secrets, such as Wireguard keys, passwords, API Keys, etc.
From my home PC, I set up a docker
[context](https://docs.docker.com/engine/manage-resources/contexts/) that allows
me to manage the Docker daemon running in my homelab. This works great, because
I can just switch to my homelab's Docker context, start or stop services, and
not have to worry about `scp`ing source files or anything. Plus, all my secrets
are in my `.env` files, so I'm not committing any secrets to source control.

However, there's one problem with this: all my secrets in my `.env` files exist
only on my home PC. If I'm on-the-go and need to work on my homelab from my
laptop, I don't have my `.env` files.

There are many different ways to securely share `.env` files between teams, but
it's just me here. No one else is going to be working on my homelab. So with
that fact, and the fact that my Gitea server is private, it would probably be
just fine to commit my `.env` files to VCS.

But I don't wanna do that. I want to securely share my `.env` files between
machines, and I don't want to learn a new service, like [HashiCorp
Vault](https://www.hashicorp.com/en/products/vault) or [Google's Secrets
Manager](https://cloud.google.com/security/products/secret-manager), and I
*certainly* don't want to pay for it. So, I came up with an alternative.

I present to you: [GnuPG](https://www.gnupg.org/)!

Okay, I'm probably not the first person to think of this, but I came up with the
idea on my own at least.

Essentially, I find all my `.env` files, combine them into a single file,
encrypt them, and save that encrypted file to version control.

# Shell-fu

Here's a one-liner I use:
```shell
fd -HI -t f .env -X tail -v -c +0 {} | gpg --output env.gpg --encrypt --recipient wes@weskoerber.com
```

Here's a quick breakdown of that command:

- `fd`: [fd](https://github.com/sharkdp/fd) is a better alternative to [GNU
  find](https://www.gnu.org/software/findutils/manual/html_mono/find.html). If
  you don't have it, you should really check it out.
- `-HI`: Include hidden files, and files that are ignored by VCS.
- `-t f`: Include files only in the results (exclude directories, block devices,
  etc.).
- `.env`: Find files named `.env`.
- `-X`: Run the following command, passing *all* results to the command.
- `tail -v -c +0`: print the file to `stdout` (`tail`), always printing filename
  headers (`-v`), starting at byte 0 (`-c +0`), with the files `{}` (passed from
  `fd`).
- `| gpg --output env.gpg --encrypt --recipient wes@weskoerber.com`: Pass
  `tail`'s output to `gpg` and encrypt the file, saving it to `env.gpg`.

Here's a quick demo of that `tail` command:
```
$ ls
hello  world

$ tail -v -c +0 *
==> hello <==
hello

==> world <==
world
```

Pretty neat, huh? With `-c +0`, `tail` is basically functioning as `cat` here,
but it prints the name of the file before its contents. This allows me to know
where the file exists, and I can parse that and write the contents to the
appropriate location.

[^1]: I still think YNAB is a good deal. If you use it carefully, you'll
probably save your subscription cost several time over if you really pay
attention to and stick to your budget.

[^2]: This was part of an affiliate deal between RackNerd and Pangolin. See the
    [Recommended
    Options](https://docs.pangolin.net/self-host/choosing-a-vps#recommended-options)
    page on Pangolin's docs for more info.

[^3]: I have an [affiliate link](https://my.racknerd.com/aff.php?aff=18387) as
    well, so if you'd like to support me, use it to sign up for services and
    I'll get a small commission. However, I'd rather you use [Pangolin's
    affiliate link](https://my.racknerd.com/aff.php?aff=13788&pid=903) instead
    to support them!
