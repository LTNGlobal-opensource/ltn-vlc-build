# ltn-vlc-build
Build script and dependencies

This package provides the build scripts to reliably build the VLC source tree
used by LTN Global.  This allows us to ensure that all build options are 
provided in a consistent manner.

We've also bundled the third-party dependencies into this repository, which
will allow us to build the tree going forward even if those dependencies
get moved or disappear from the Internet entirely (as has already started
to happen in several cases)

The build.sh script was derived from the original "HOWTO" script that Jacob
Green provided, with some minor tweaks to improve its robustness.  The most
notable change is that the contrib tree is now hard-coded with a list of
components to explicitly include, as opposed to the previous model where
everything was included and there was a list of things to leave out.

## Building

Run the following script:

`./build.sh`

The process will result in a file named "vlc.tar.bz2" which contains the final build.
