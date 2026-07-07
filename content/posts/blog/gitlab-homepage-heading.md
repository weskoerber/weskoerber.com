+++
title = "My irrational anger at Gitlab's homepage headings"
date = "2026-07-07"
+++

We use a self-hosted instance of Gitlab at work. I've always felt that Gitlab
has been okay as a code forge, and when we set it up several years ago it was
certainly the most feature-complete tool for our team.

The last few updates have been... interesting.

I don't use Gitlab to it's full marketed potential. I mainly use it for keeping
track of issues, merge requests, the occasional milestone, and CI/CD pipelines.
We don't use Agile or any of those other bureaucratic project management
ideologies; we just get stuff done.

## The good

Starting with the good updates, I really like what they did with the homepage.
It shows a lot of good information at a glance, with lots of links to
frequently-accessed projects, latest updates from team members, and overall
shows a fairly decent picture of what's on my plate at a high level.

Issue thread resolution is another, sometimes overlooked feature. Sometimes we
have discussions on issues in the design phase of a project or feature. These
discussions can move very quickly, so being able to resolve old threads and keep
focus on what's left to solve is really nice. This is the same with merge
requests, but I think thread resolution on merge requests have been around for a
while now.

Another feature that's really nice is auto-merging when pipelines succeed. If a
job is picked up on a slow runner, but all threads are resolved and the MR is
approved, we used to have to wait for the runner to succeed, and our Windows
runners are as slow as molasses. Now, we can just hit the auto-merge button and
we don't have to babysit the job just to get the MR merged.

Linking between issues, merge requests, pipelines, jobs, commits, and projects
is pretty well-implemented too. When the name or path of a project changes, the
links get updated, which is a *really* underrated feature, and significant
time-saver. We have hundreds of projects, and probably thousands of links to
various items, so updating them all by-hand is pretty much a non-starter.

Automated releases and deployments is nice too, but that's just about the bare
minimum these days.

However, with every good feature, it seems they ship 3 bad ones.

## Issues (Work items)

For some reason, they decided to change the "Issues" page to "Work items." It
took me an embarrassingly long time to find where my issues went after we updated
out instance. I initially thought our update was broken! Nope, just a rename
nobody asked for.

There's no longer dedicated filters for showing the state of an issue (work item) now --
i.e. open/closed. It's baked into the filters. You can create a "view" for your
project's issues (work items), but you have to create that same view **for every
single one of your projects**! We have hundreds of projects, that ain't
happening.

Also, the kanban-esque boards -- previously called "Issues boards" -- can you
guess what they're called now? That's right! **Issue boards!** Did they forget
about this or was it an intentional omission? Either way, it's annoying. It's
like a little reminder of when times were better. But then again, "Work item
boards" is a bit of a mouthful.

They also redesigned the issues (work items) UI for like the tenth time. When
you click on an issue (work item), it used to navigate to that issue. Now, it
opens in this annoying vertical split. "But Wes, wouldn't that be more useful,
since you can look at the issues (work items) list instead of taking you to a
completely different page?" Ah, yes. Thank you for pointing that out, astute
reader. That, in fact, *would* be nice! However, it doesn't! The moment you page
forward or back, *the vertical split goes away.* And if your screen isn't wide
enough, it opens in this weird flyout that covers almost the entire page so that
you can't see anything behind it. At that point, what's the purpose of a flyout?
Just take me to the page. *So many times* I open an issue (work item) and want
it to *stay* open, but I end up touching it wrong and it closes. When you're
doing this 500 times a day, it gets really frustrating.

## Runner cache cleanup (or lack thereof)

CI/CD runner caches don't get cleaned up. I'm not sure if this is a new thing or
just something that showed up on the radar because our disk nearly filled up.

Most artifacts have automatic cleanup: image registry, package registry, job
artifacts, etc. However, the runner artifacts don't get cleaned up
automatically. This means I have to periodically run a sketchy docker command to
clean them up:

``` sh
docker volume rm $(docker volume ls -q --filter name=runner.*cache.*)
```

## Duo

Who needs another AI chatbot. Leave me the hell alone.

## Search absolutely blows

If you're looking for a code forge whose search capabilities are absolutely
inept, Gitlab is for you!

There's this one project I frequent that's not available at all in the search
results. I have no idea why. When I type the project's name with case
sensitivity, the project refuses to show up in search results. Gitlab even has
this super helpful syntax to search only project names by prefixing the search
key with `:`. Even that doesn't work. Oh, but you bet it shows me other project
names instead!

It looks like there's an
[advanced](https://docs.gitlab.com/user/search/#specify-a-search-type) search
type, but that requires me to add a URL parameter. Like, what?? I mean, what are
we doing here?

If my memory serves me right, a fully-featured search used to be paywalled. It
doesn't appear to be anymore, thankfully.

## Homepage heading

All this complaining brings me to this: the stupid homepage heading. Believe it
or not, the reason for this whole blog post is this single "feature."

It's a culmination of receiving a thousand little papercuts using Gitlab day in
and day out for several years, only to see this stupid thing.

It's an
[`h1`](https://developer.mozilla.org/en-US/docs/Web/HTML/Reference/Elements/Heading_Elements)
element that shows a "clever" phrase every time you load the page. Right there
on the top. Big and bold. The first thing you see. And some of them make my
blood boil:
- "It's a bug, not a feature"
- "It all started with a commit"
- "It's Tuesday, let's code"
- "Ready when you are"

This makes me irrationally angry for a couple reasons.

First, and foremost, it reads like an LLM. I can't stand the LLM dialect. I can
almost guarantee someone asked ChatGPT to "generate 5000 'clever' phrases about
coding and getting stuff done."

Secondly, and very closely following my first gripe, is that there are so many
parts of Gitlab that are unpolished, unfinished, half-baked, half-changed, or
just flat out don't work.

I really wish they would just spend time improving the core functionality of the
service and making my life easier as someone who has to use it, rather than
making the biggest, most noticeable part of the page so useless. I mean, it would
be just as simple to add a button to enable advanced search on the search UI,
and that would actually provide a tangible improvement.

## Conclusion and Apologies

Maybe part of my frustration has been amplified by the larger enshittification
of the industry for the past few years.
[Unfortunately](https://github.com/resources/insights/2026-pricing-changes-for-github-actions),
[it's](https://sheep.horse/2025/4/yo_google%2C_thanks_for_the_ai_overview_but_your_sea.html)
[only](https://en.wikipedia.org/wiki/Reddit_API_controversy)
[getting](https://blog.playstation.com/2026/07/01/physical-disc-production-ending-in-january-2028-for-new-games-releasing-on-playstation-consoles/)
[worse](https://www.windowscentral.com/microsoft/windows-11/2025-has-been-an-awful-year-for-windows-11-with-infuriating-bugs-and-constant-unwanted-features).

Now look, I understand that open source maintainers are experiencing
contributions at an [unprecedented
volume](https://kristoff.it/blog/contributor-poker-and-ai/) prompting them to
introduce [new techniques](https://github.com/mitchellh/vouch) to manage. I
really try to manage my expectations, understanding that the people maintaining
much of the world's most loved software is open source and maintained by the
community's free time. I try to chip in sometimes when I have the time, and
donate monthly to my favorite projects.

But Gitlab is a publicly traded company. Their [2026 Q1 financial
reports](https://ir.gitlab.com/news/news-details/2025/GitLab-Reports-First-Quarter-Fiscal-Year-2026-Financial-Results/default.aspx)
showed a total revenue of almost $215 million, a 27% year-over-year increase,
and a nearly $5 million increase from [2025
Q4](https://ir.gitlab.com/news/news-details/2025/GitLab-Reports-Fourth-Quarter-and-Full-Fiscal-Year-2025-Financial-Results/default.aspx).
Gitlab's 2025 revenue was over $750 million. They don't get the same treatment
that those labor-of-love projects get. I feel like I'm allowed to criticize them
more because of it.

I bet there are some seriously good programmers and engineers working at Gitlab.
This is not a dig at them. Rather, this sort of frustration I'm feeling seems
like one management misstep after another. With Gitlab in a prime position to
dethrone Github after several missteps of their own, the fact that they aren't
seizing the opportunity kind of reinforces my theory.
