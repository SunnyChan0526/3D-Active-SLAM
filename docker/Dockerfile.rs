# Layer on top of activeslam:noetic that replaces ROS's librealsense 2.50 with a
# source build of a newer librealsense (RSUSB backend: no kernel patches needed,
# works on Jetson). The old image is left untouched.
#
# Build context is a separate folder (not the repo) holding this file plus:
#   librealsense.tar.gz       (github.com/IntelRealSense/librealsense/archive/refs/tags/vX.Y.Z.tar.gz)
#   ca-certificates.crt       (host /etc/ssl/certs/ca-certificates.crt; the image's bundle is too old for GitHub)
#   docker build -f Dockerfile.rs -t activeslam:noetic-rs254 --network host \
#     --build-arg http_proxy=... --build-arg https_proxy=... .
# Use:
#   ACTIVESLAM_IMAGE=activeslam:noetic-rs254 docker/run.sh ...
# then rebuild realsense_ws once (catkin clean/build realsense2_camera).
ARG BASE=activeslam:noetic
FROM ${BASE}
ARG JOBS=6

USER root
COPY ca-certificates.crt /tmp/build-ca.crt
COPY librealsense.tar.gz /tmp/librealsense.tar.gz
# CA bundle used only while building (cmake fetches third-party code over HTTPS).
ENV SSL_CERT_FILE=/tmp/build-ca.crt CURL_CA_BUNDLE=/tmp/build-ca.crt GIT_SSL_CAINFO=/tmp/build-ca.crt
RUN set -e; \
    dpkg -r --force-depends ros-noetic-librealsense2; \
    src=/tmp/librealsense; mkdir -p "$src"; \
    tar -xzf /tmp/librealsense.tar.gz -C "$src" --strip-components=1; rm /tmp/librealsense.tar.gz; \
    cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DFORCE_RSUSB_BACKEND=ON -DBUILD_WITH_CUDA=OFF \
      -DBUILD_EXAMPLES=OFF -DBUILD_GRAPHICAL_EXAMPLES=OFF -DBUILD_TOOLS=ON \
      -DBUILD_UNIT_TESTS=OFF -DBUILD_PYTHON_BINDINGS=OFF -DCHECK_FOR_UPDATES=OFF; \
    cmake --build "$src/build" --parallel "$JOBS"; \
    cmake --install "$src/build"; \
    ldconfig; rm -rf "$src" /tmp/build-ca.crt; \
    rs-enumerate-devices --version || true
ENV SSL_CERT_FILE= CURL_CA_BUNDLE= GIT_SSL_CAINFO=

ARG USERNAME=evil1323
USER $USERNAME
