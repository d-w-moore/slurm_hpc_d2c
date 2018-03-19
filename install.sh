#!/usr/bin/env bash

DIR=$(dirname "$0")
. "$DIR/error.rc"
#cd "$DIR"

grep -w irods /etc/passwd >/dev/null 2>&1 || die NO_IRODS_USER

# ============================================================================

mkdir -p ~/github

(
  cd ~/github && \
  git clone http://github.com/dun/munge.git && \
  cd munge && \
  ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var && \
  make && \
  sudo make install
)

[ $? -eq 0 ] || die MUNGE_BUILD

# ============================================================================

if ! grep ^munge: /etc/passwd  >/dev/null 2>&1 ; then
  echo >&2 "Adding 'munge' system user"
  sudo adduser --system --group --no-create-home munge && \
  sudo dd if=/dev/urandom of=/etc/munge/munge.key  bs=1k count=1  && \
  sudo chmod 600 /etc/munge/munge.key  && \
  sudo chown munge:munge /etc/munge/munge.key
fi

[ $? -eq 0 ] || die MUNGE_USER

# ============================================================================

sudo /etc/init.d/munge start ; echo -n "starting 'munge' daemon ..." >&2
sleep 2 ; echo >&2

[ $? -eq 0 ] || die MUNGED_START

if pgrep munged  2>/dev/null >&2 ; then
  sudo update-rc.d munge defaults
else
  echo >&2 "Not able to start munge ; aborting install."
fi

[ $? -eq 0 ] || die MUNGED_INSTALL

(
  cd ~/github					&& \
  git clone http://github.com/SchedMD/slurm.git	&& \
  cd slurm 					&& \
  git checkout slurm-17-11-4-1			&& \
  ./configure --with-munge=/usr			&& \
  make						&& \
  make check					&& \
  sudo make install
)

[ $? -eq 0 ] || die SLURM_BUILD

sudo env -i	$(/usr/local/sbin/slurmd -C)			\
		USER=irods					\
		perl -pe 's/\$(\w+)/$ENV{$1}/ge unless /^\s*#/'	\
		< "$DIR"/slurm.conf.template			\
		> /usr/local/etc/slurm.conf

[ $? -eq 0 ] || die SLURM_CONFIG

CR=$'\n'
SLURM1="/usr/local/sbin/slurmctld"
SLURM2="/usr/local/sbin/slurmd"

# --------------------------------------------------------------------
# start up SLURM daemons and make their launch a part of /etc/rc.local

sudo pkill 'slurm(ctl|)d' >/dev/null 2>&1
sudo su - -c "$SLURM1 && $SLURM2" 
sleep 2
if [ $(pgrep 'slurm(ctl|)d' | wc -l) -eq 2 ]; then
  grep slurm /etc/rc.local >/dev/null 2>&1 || 
  sudo env -i SLURMDAEMONS="${SLURM1}${CR}${SLURM2}${CR}" \
	perl -i.orig -pe 's[(\s*exit\s+0\s*)\n*$][$ENV{SLURMDAEMONS}$1]s' \
	/etc/rc.local 
else
  die SLURM_START
fi

[ $? -eq 0 ] || die SLURM_INSTALL

