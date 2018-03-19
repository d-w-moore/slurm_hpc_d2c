#!/usr/bin/env bash

DIR=$(dirname "$0")
. "$DIR/error.rc"

cd "$DIR"

# ============================================================================

(
  git clone http://github.com/dun/munge.git && \
  cd munge && \
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var && \
  make && \
  sudo make install
)

# ============================================================================

if ! grep ^munge: /etc/passwd  >/dev/null 2>&1 ; then
  echo >&2 "Adding 'munge' system user"
  sudo adduser --system --group --no-create-home munge
fi

# ============================================================================

sudo /etc/init.d/munge
pgrep munged  && \
sudo update-rc.d munge defaults

(
  git clone http://github.com/SchedMD/slurm.git && \
  cd slurm && \
  git checkout slurm-17-11-4-1 && \
  ./configure --with-munge=/usr
  make && \
  make check && \
  sudo make install
)

sudo env -i	$(/usr/local/sbin/slurmd -C)	\
		USER=irods			\
		perl -pe 's/\$(\w+)/$ENV{$1}/ge unless /^\s*#/' < slurm.conf.template 	\
		> /usr/local/etc/slurm.conf
