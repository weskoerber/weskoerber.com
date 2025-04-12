+++
title = "!! in Vim"
date = "2025-04-12"
+++

# TL;DR

Today I learned about VIM's `!!` command, and it's amazing! It works by sending
the selected range to an external program's `stdin`, and replaces those lines
with its `stdout`.

# Using an empty range

Sometimes you may want to put the contents of a file directly into you buffer,
but you don't want to open up the file in a separate buffer, yank the contents,
and put them in your desired buffer.

`readme.txt`
```
This is a readme file.

I need this file in a buffer!
```

`my_buffer`
```
This is my buffer. I want the contents of the `readme.txt` file to go in this
file!


```

After switching to normal mode and navigating to the empty line (the last line
in `my_buffer`), typing `!!cat readme.txt` will but the contents of
`readme.txt` into my buffer, starting at my cursor!

`my_buffer`
```
This is my buffer. I want the contents of the `readme.txt` file to go in this
file!

This is a readme file.

I need this file in a buffer!
```

# Replacing a single line

Sometimes you want to view the content of a command's `stdout` in Vim. Usually
what I do is run the command and pipe `stdout` into Vim's `stdin` (i.e. `vim
-`).

Here's an example using the `!!` command. Say you have a JSON file that's been
[minified](https://en.wikipedia.org/wiki/Minification_(programming)) and you
want to un-minify it. To accomplish this, we can use
[`jq`](https://jqlang.org/) to read the file and put it's formatted JSON output
into our buffer.

```json
{"id":123,"name":"John Doe","age":34,"address":{"street":"123 Fake St","city":"Nowhere","zip":"98765"},"hobbies":["coding","gaming","nothing"],"active":true,"scores":{"math":95,"science":88},"lastLogin":"2023-10-05T14:30:00Z"}
```

After switching to Vim's normal mode and putting my cursor over the line with
the minified JSON, when I type `!!jq<CR>`, the single line of minified JSON is
replaced with multiple lines of perfectly-formatted JSON -- magic!

```json
{
  "id": 123,
  "name": "John Doe",
  "age": 34,
  "address": {
    "street": "123 Fake St",
    "city": "Nowhere",
    "zip": "98765"
  },
  "hobbies": [
    "coding",
    "gaming",
    "nothing"
  ],
  "active": true,
  "scores": {
    "math": 95,
    "science": 88
  },
  "lastLogin": "2023-10-05T14:30:00Z"
}
```

# Replacing a range

Here's another contrived example. You have a list of strings and you need to
sort them and edit them in a buffer. Let's ignore that Vim has a built-in sort
command (`:h sort`), so we need to use `sort` from GNU coreutils. One way you
might accomplish this task is:
1. save the list of strings to a file
2. run GNU `sort` on the file, saving the output to a separate file
3. open the sorted file in Vim
4. yank the sorted lines
5. put the sorted lines into the desired location in your destination buffer

This is a pretty lengthy task. Maybe we can shorten it. How about we:
1. save the list of strings to a file
2. run GNU `sort` on the file, piping the output to Vim's `stdin` (`vim -`)
3. yank the sorted lines
4. put the sorted lines into the desired location in your destination buffer

That's better- we got rid of the intermediate file containing our sorted
strings, but it's still a bit lengthy.

There's probably some other ways you can accomplish this process a bit quicker,
but instead of going over every possible scenario, let's see how you'd do this
with the `!!` command:
1. using the range of strings, run `!!sort`

Yep, that's it. One step. Let's have a closer look.

```
Here are some notes. I need these to keep organized!

TO-DO List:
- fix the leaky faucet
- walk the dog
- take out the trash

Grocery List:
- milk
- ground beef
- butter
- eggs
```

Let's say I want to sort my grocery list- I think it'll be easier to take
inventory of what I need if it's in alphabetical order. I'll position my cursor
on the "butter" line in my grocery list and -- in normal mode -- type
`4!!sort<CR>`. *Et voilà* -- my grocery list is now sorted:

```
Here are some notes. I need these to keep organized!

TO-DO List:
- fix the leaky faucet
- walk the dog
- take out the trash

Grocery List:
- butter
- eggs
- ground beef
- milk
```
