# syntax=docker/dockerfile:1.27@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e
#
# CADVerify sandbox: pinned OpenSCAD + Python analysis stack + xvfb + PrusaSlicer. The X libraries
# are what the gmsh wheel links against (cadcheck/fea.py); it opens no window. PrusaSlicer, the engine
# Bambu Studio forked from, runs from its command line (cadcheck/slicer.py), with no display; its GUI
# libraries are about 900 MB of this image.
# Every input is pinned: images by digest, Debian packages by exact version from a fixed
# snapshot.debian.org timestamp, Python by exact version and Python packages by uv.lock.
#
#   docker build -t cadverify-sandbox .

FROM ghcr.io/astral-sh/uv:0.9.30@sha256:538e0b39736e7feae937a65983e49d2ab75e1559d35041f9878b7b7e51de91e4 AS uv

# OpenSCAD 2026.10.26 (git e57210129) with the Manifold backend, built by the OpenSCAD project
# on Debian 13. There is no stable release after 2021.01; this dated tag is a nightly.
FROM openscad/openscad:dev.2026-10-26@sha256:3268ba487a3b92e605f44431c890d71ed576d5cc71a249c24a4af489d88990c6 AS sandbox

# The snapshot the base image was built from (see the comments in its debian.sources) decides what
# is installed: apt checks every file against its signed index. Debian's mirror is there for the
# bytes, listed first with priority 1 so that it never chooses a version: the snapshot answers 503
# to long downloads, which cost a failed build of 33 minutes, and a file the mirror no longer has
# still comes from the snapshot.
# Plain HTTP because the image has no CA bundle; apt still verifies the archive signatures.
ARG DEBIAN_SNAPSHOT=20261020T213255Z
RUN cat > /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: http://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp

Types: deb
URIs: http://deb.debian.org/debian-security
Suites: trixie-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp

Types: deb
URIs: http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}
Suites: trixie trixie-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
Check-Valid-Until: no

Types: deb
URIs: http://snapshot.debian.org/archive/debian-security/${DEBIAN_SNAPSHOT}
Suites: trixie-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
Check-Valid-Until: no
EOF
RUN cat > /etc/apt/preferences.d/snapshot-decides <<EOF
Package: *
Pin: origin deb.debian.org
Pin-Priority: 1
EOF
RUN apt-get update -o Acquire::Retries=5 \
    && apt-get install -y --no-install-recommends -o Acquire::Retries=5 \
        xvfb=2:21.1.16-1.3+deb13u4 \
        xauth=1:1.1.2-1.1 \
        libxcursor1=1:1.2.3-1 \
        libxft2=2.3.6-1+b4 \
        libxinerama1=2:1.1.4-3+b4 \
        prusa-slicer=2.9.2+dfsg-1 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv
ENV UV_PYTHON=3.12.12 \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_PYTHON_PREFERENCE=only-managed \
    UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_NO_CACHE=1
RUN uv python install --no-bin 3.12.12

WORKDIR /app
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --locked --no-install-project
COPY src ./src
COPY tests ./tests
RUN uv sync --locked --no-editable

RUN useradd --uid 1000 --create-home cadverify
# The solver's threads match the CPUs a verification has, whatever the host shows: more than that
# only fight for the quota, and the same count gives the same numbers on every machine.
ENV PATH=/opt/venv/bin:$PATH \
    OMP_NUM_THREADS=2 \
    OPENBLAS_NUM_THREADS=2 \
    OPENSCAD_BIN=/usr/local/bin/openscad \
    OPENSCADPATH=/opt/venv/lib/python3.12/site-packages/cadverify/cadcheck/standard \
    CADVERIFY_SANDBOX=1 \
    MPLCONFIGDIR=/tmp/matplotlib
USER cadverify
WORKDIR /work
CMD ["cadcheck", "--help"]
