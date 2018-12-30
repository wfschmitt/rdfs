FROM ubuntu:latest
RUN apt-get update -y
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get -y upgrade
RUN apt-get install apt-utils -y
# RUN echo "deb http://security.ubuntu.com/ubuntu xenial-security main restricted multiverse" >> /etc/apt/sources.list


# Required Packages for the Host Development System
# http://www.yoctoproject.org/docs/latest/mega-manual/mega-manual.html
# required-packages-for-the-host-development-system
RUN apt-get install -y gawk wget git-core diffstat unzip texinfo gcc-multilib \
     build-essential chrpath socat cpio  \
     xz-utils debianutils iputils-ping pkg-config  \
     git screen tmux
#RUN echo "deb http://ppa.launchpad.net/rael-gc/rvm/ubuntu/ bionic main" >> /etc/apt/sources.list
# Additional host packages required by poky/scripts/wic
RUN apt-get install curl tree vim htop mc rxvt screen tmux ruby rake ruby-bundler  \
  ri bundler ctags vim-doc vim-scripts ruby-dev -y
RUN apt-get update && apt-get -y upgrade

# Create user "jenkins"
RUN id jenkins 2>/dev/null || useradd --uid 20000 --create-home jenkins

# Create a non-root user that will perform the actual build
RUN id werner 2>/dev/null || useradd --uid 1000 --create-home werner
RUN id build  2>/dev/null || useradd --uid 10000 --create-home build
RUN apt-get install -y sudo
RUN echo "build ALL=(ALL) NOPASSWD: ALL" | tee -a /etc/sudoers
RUN echo "werner ALL=(ALL) NOPASSWD: ALL" | tee -a /etc/sudoers
#RUN echo "[user] \#
#        mail = werner.schmitt@harman.com \
#        name = werner schmitt \
#        email = werner.schmitt@harman.com \
#[credential] \
#        helper = store \
#" | tee -a /home/build/.gitconfig
#

#RUN wget https://github.com/jgm/pandoc/releases/download/2.1.3/pandoc-2.1.3-1-amd64.deb
#RUN dpkg -i pandoc-*.deb


ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qy && \
    apt-get install libnet-ifconfig-wrapper-perl net-tools -y autoconf automake bison libffi-dev libgdbm-dev libncurses5-dev libsqlite3-dev libtool libyaml-dev sqlite3 zlib1g-dev libreadline-dev libssl-dev curl ca-certificates gnupg2 build-essential


#RUN gpg2 --keyserver hkp://keys.gnupg.net --recv-keys D39DC0E3
RUN curl -sSL https://get.rvm.io | bash
RUN /bin/bash -l -c ". /etc/profile.d/rvm.sh && rvm install 2.5"
#RUN /bin/bash -l -c ". /etc/profile.d/rvm.sh && rvm install 2.4"
#RUN /bin/bash -l -c ". /etc/profile.d/rvm.sh && rvm install 2.3"
# The entry point here is an initialization process,
# it will be used as arguments for e.g.
# `docker run` command
ENTRYPOINT ["/bin/bash", "-l", "-c"]

USER werner
WORKDIR /home/werner
RUN sudo chown werner.werner /home/werner -R
RUN sudo usermod -a -G rvm build
RUN sudo usermod -a -G rvm werner
RUN sudo usermod -a -G rvm root

CMD "/bin/bash"
# EOF
