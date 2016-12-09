# Yet Another Mac Admin Scripts Repository
Like most Mac IT people, I often write scripts to _do the thing_. These are mine. Feel free to borrow/use as you see fit.

# A few assumptions
Most of my scripts make a few assumptions about what's on the system, and where. You will want to keep these in mind:

 * cocoaDialog: I use [Locee's fork of cocoaDialog 3 beta](https://github.com/loceee/cocoadialog), which will display over `loginwindow` and work at logout. Generally, I hide this in `/Library/Application Support/JAMF/bin/` because _reasons_ - you can put it wherever you'd like. Just be sure to update the variables.
 * progressScreen: For the DEP Deploy, I make use of a slightly modified version of [Jason Tratta's ProgressScreen](https://github.com/jason-tratta/ProgressScreen). The default one will work fine, but you may need to pass a extra line or two of Apple Script to hide the exit button and make it full screen by default. YMMV.

As with anything, test before you deploy, and know that artesianal scripts come without any warranty promise of their _doing the thing_.
