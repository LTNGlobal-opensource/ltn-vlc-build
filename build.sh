#!/bin/sh

# Bail out if any command fails...
set -e

GITREPO=https://github.com/LTNGlobal-opensource/vlc-sdi.git
GITBRANCH=ltn-scte-35
BLACKMAGIC_ZIP=Blackmagic_DeckLink_SDK_10.1.zip
BLACKMAGIC_SHA512=db4f0c0432839b33f1a12788ebab8e5d106edb91c35a9d8754d9199e85c6cf74d1e1aeaf4ba9328b3c7fd71a4574b9f5cff4a7688aa9ceb438b4d7f1a3495c17

# Setup the BlackMagic SDK
if [ ! -d blackmagic_sdk ]; then
    echo "$BLACKMAGIC_SHA512  $BLACKMAGIC_ZIP" | sha512sum --check - || exit 1
    unzip -oq $BLACKMAGIC_ZIP
    ln -Tfs ./Blackmagic\ DeckLink\ SDK\ 10.1/Linux blackmagic_sdk
fi

BITSTREAM_REPO=https://code.videolan.org/videolan/bitstream.git
BITSTREAM_BRANCH=ce288cb355843d4252f52f4e0a07528d04b8bd2a
KLVANC_REPO=https://github.com/stoth68000/libklvanc.git
KLVANC_BRANCH=
KLSCTE35_REPO=https://github.com/stoth68000/libklscte35.git
KLSCTE35_BRANCH=

# 1) SOURCE CODE
# Exact reproducibility guaranteed by git SHA1 hash

if [ ! -d vlc ]; then
	git clone $GITREPO vlc
	cd vlc
	if [ "$GITBRANCH" != "" ]; then
	    echo "Switching to branch [$GITBRANCH]..."
	    git checkout $GITBRANCH
	fi
else
	cd vlc
fi

# 2) BUILD TOOLS (yasm, autotools)

cp ../tools-tarballs/ragel-6.8.tar.gz extras/tools/
cd extras/tools
if [ -d build/bin ]; then
	export PATH=$PWD/build/bin:$PATH
fi

./bootstrap
make -j4
cd ../..

# 3) DEPENDENCIES (ffmpeg, libdvbpsi, ..)
# Exact reproducibility guaranteed by sha512sums

# Provide the tarballs explicitly rather than downloading
# them (since they may disappear from the Internet at some pont)
cp ../contrib-tarballs/* contrib/tarballs

CONTRIBDIR=`pwd`/contrib/centos
CONTRIB_BUILDROOT=`pwd`/contrib/`cc -dumpmachine`
mkdir -p $CONTRIBDIR
cd $CONTRIBDIR

# While it may seem redundant to include "--disable-sout" and "--disable-disc"
# when immediately followed by "--disable-all", those two are special cases
# in the bootstrap script which impact whether BUILD_ENCODERS gets specified,
# and hence whether vpx and lame get included as implicit dependencies.  Hence,
# they need to be explicitly present despite being followed by --disable-all.

../bootstrap --disable-sout --disable-disc --disable-all --enable-dca --enable-dvbpsi --enable-faad2 --enable-ffmpeg --enable-gettext --enable-gsm --enable-libxml2 --enable-mad --enable-openjpeg --enable-opus --enable-png --enable-samplerate --enable-zlib

# Build the deps
echo EXTRA_CFLAGS := -fPIC >> config.mak
make -j8

cd ../../../

# Build Kernel Labs dependencies
if [ ! -d bitstream ]; then
	git clone $BITSTREAM_REPO bitstream
	cd bitstream
	if [ "$BITSTREAM_BRANCH" != "" ]; then
	    echo "Switching to branch [$BITSTREAM_BRANCH]..."
	    git checkout $BITSTREAM_BRANCH
	fi
	PREFIX=${CONTRIB_BUILDROOT} make install
	cd ..
fi

if [ ! -d libklvanc ]; then
	git clone $KLVANC_REPO libklvanc
	cd libklvanc
	if [ "$KLVANC_BRANCH" != "" ]; then
	    echo "Switching to branch [$KLVANC_BRANCH]..."
	    git checkout $KLVANC_BRANCH
	fi
	./autogen.sh --build
	CPPFLAGS=-I${CONTRIB_BUILDROOT}/include LDFLAGS=-L${CONTRIB_BUILDROOT}/lib ./configure --disable-shared
	make
	make install prefix=${CONTRIB_BUILDROOT}
	cd ..
fi

if [ ! -d libklscte35 ]; then
	git clone $KLSCTE35_REPO libklscte35
	cd libklscte35
	if [ "$KLSCTE35_BRANCH" != "" ]; then
	    echo "Switching to branch [$KLSCTE35_BRANCH]..."
	    git checkout $KLSCTE35_BRANCH
	fi
	./autogen.sh --build
	CPPFLAGS=-I${CONTRIB_BUILDROOT}/include LDFLAGS=-L${CONTRIB_BUILDROOT}/lib ./configure --disable-shared
	make
	make install prefix=${CONTRIB_BUILDROOT}
	cd ..
fi

# Build VLC itself
cd vlc
./bootstrap
./configure --disable-nls --disable-xcb --disable-xvideo --disable-glx --disable-alsa --disable-sdl --disable-dbus --disable-lua --disable-mad --disable-a52 --disable-libgcrypt --disable-chromaprint --disable-qt --disable-skins2  --disable-live555  --disable-libva --disable-freetype --with-decklink-sdk=`cd ../blackmagic_sdk && pwd` --prefix=/usr
make -j8

# Install to a temporary directory and remove a bunch of unneeded stuff
mkdir -p inst
make DESTDIR=$PWD/inst install
cd inst
cd usr
rm -fr include share
rm -f bin/rvlc bin/cvlc bin/vlc-wrapper
rm -fr lib/pkgconfig
rm -f lib/vlc/libcompat.a lib/vlc/vlc-cache-gen
find lib -name \*.la -exec rm -f {} \;
cd ..

# Create the final tarball
tar czf ../../vlc.tar.gz usr
