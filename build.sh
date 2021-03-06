#!/bin/sh

# Bail out if any command fails...
set -e

GITREPO=https://github.com/LTNGlobal-opensource/vlc-sdi.git
GITBRANCH=vid.vlc.1.1.7
KLVANC_REPO=https://github.com/LTNGlobal-opensource/libklvanc.git
KLVANC_BRANCH=vid.obe.1.1.5
KLSCTE35_REPO=https://github.com/LTNGlobal-opensource/libklscte35.git
KLSCTE35_BRANCH=vid.obe.1.1.2
BMSDK_REPO=https://github.com/LTNGlobal-opensource/bmsdk.git

# Make available the BlackMagic SDK
if [ ! -d bmsdk ]; then
    git clone $BMSDK_REPO
fi
if [ `uname -s` = "Darwin" ]; then
    PLAT=Mac
else
    PLAT=Linux
fi
BMSDK_10_8_5=$PWD/bmsdk/10.8.5/$PLAT
BMSDK_10_1_1=$PWD/bmsdk/10.1.1/$PLAT

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
if [ ! -d libklvanc ]; then
	git clone $KLVANC_REPO libklvanc
	cd libklvanc
	if [ "$KLVANC_BRANCH" != "" ]; then
	    echo "Switching to branch [$KLVANC_BRANCH]..."
	    git checkout $KLVANC_BRANCH
	fi
	./autogen.sh --build
	CPPFLAGS=-I${CONTRIB_BUILDROOT}/include LDFLAGS=-L${CONTRIB_BUILDROOT}/lib ./configure --disable-shared --prefix=${CONTRIB_BUILDROOT}
	make
	make install
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
	CPPFLAGS=-I${CONTRIB_BUILDROOT}/include LDFLAGS=-L${CONTRIB_BUILDROOT}/lib ./configure --disable-shared --prefix=${CONTRIB_BUILDROOT}
	make
	make install
	cd ..
fi

build_vlc() {
    GITVER=`echo $1 | sed 's/^vid.vlc.//'`
    BMSDK_DIR=$2
    BMVERSION=`cat $BMSDK_DIR/include/DeckLinkAPIVersion.h | grep BLACKMAGIC_DECKLINK_API_VERSION_STRING | awk '{print $3}'|sed -e 's/^"//' -e 's/"$//'`

    echo "Building VLC $GITVER for BlackMagic SDK version $BMVERSION"

    cd vlc
    ./bootstrap
    ./configure --disable-nls --disable-xcb --disable-xvideo --disable-glx --disable-alsa --disable-sdl --disable-dbus --disable-lua --disable-mad --disable-a52 --disable-libgcrypt --disable-chromaprint --disable-qt --disable-skins2  --disable-live555  --disable-libva --disable-freetype --with-decklink-sdk=$BMSDK_DIR --prefix=/usr

    make clean
    make -j8

    # Install to a temporary directory which we can tar up
    rm -rf inst
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
    tar czf ../../vlc-$GITVER-bm$BMVERSION.tar.gz usr

    cd ../..
}

# Build ffmpeg itself
build_vlc $GITBRANCH $BMSDK_10_8_5
build_vlc $GITBRANCH $BMSDK_10_1_1
