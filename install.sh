#!/usr/bin/env bash

# ----------------------------------------------------------------------
#  Modify u14/iRODS system for running data-to-compute example on SLURM
# ----------------------------------------------------------------------

DIR=$(dirname "$0")
. "$DIR/errors.rc"

grep '^irods:' /etc/passwd >/dev/null 2>&1 || die NO_IRODS_USER

mkdir -p ~/github

f_munge_build () 
{
  (
    cd ~/github && \
    git clone http://github.com/dun/munge.git && \
    cd munge && \
    ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var && \
    make && \
    sudo make install
  )
  [ $? -eq 0 ] || warn MUNGE_BUILD
}

f_munge_user_install () 
{
  local STATUS=1
  if ! grep ^munge: /etc/passwd  >/dev/null 2>&1 ; then
    echo >&2 "Adding 'munge' system user"
    sudo adduser --system --group --no-create-home munge && \
    sudo dd if=/dev/urandom of=/etc/munge/munge.key  bs=1k count=1  && \
    sudo chmod 600 /etc/munge/munge.key  && \
    sudo mkdir -p /var/log/munge && \
    sudo chown -R munge:munge /var/run/munge /var/log/munge /etc/munge && \
    STATUS=0
  fi
  [ $STATUS -eq 0 ] || warn MUNGE_USER
}

f_munge_start ()
{
  sudo /etc/init.d/munge start ; echo -n "starting 'munge' daemon ..." >&2
  sleep 2 ; echo >&2
  [ $? -eq 0 ] || warn MUNGED_START
}

f_munge_daemon_persist ()
{
  if pgrep munged  2>/dev/null >&2 ; then
    sudo update-rc.d munge defaults
  #else
  #  echo >&2 "Not able to start munge ; aborting install."
  fi
  [ $? -eq 0 ] || warn MUNGED_PERSIST
}

f_slurm_build ()
{
  (
    cd ~/github && \
    git clone http://github.com/SchedMD/slurm.git && \
    cd slurm && \
    git checkout slurm-17-11-4-1 && \
    ./configure --with-munge=/usr && \
    make && \
    make check && \
    sudo make install
  )
  [ $? -eq 0 ] || warn SLURM_BUILD
}

f_slurm_config ()
{
  sudo env -i $(/usr/local/sbin/slurmd -C) \
                USER=irods \
                perl -pe 's/\$(\w+)/$ENV{$1}/ge unless /^\s*#/' \
                < "$DIR"/slurm.conf.template                    \
                > /tmp/slurm.conf && \
  sudo cp /tmp/slurm.conf /usr/local/etc && \
  sudo mkdir -p /var/spool/slurm{d,state} && chown -R irods:irods /var/spool/slurm{d,state}
  [ $? -eq 0 ] || warn SLURM_CONFIG
}

CR=$'\n'
SLURM1="/usr/local/sbin/slurmctld"
SLURM2="/usr/local/sbin/slurmd"

f_slurm_install ()
{
  sudo pkill 'slurm(ctl|)d' >/dev/null 2>&1
  sudo su - -c "$SLURM1 && $SLURM2" 
  sleep 2
  if [ $(pgrep 'slurm(ctl|)d' | wc -l) -eq 2 ]; then
    grep slurm /etc/rc.local >/dev/null 2>&1 || 
    sudo env -i SLURMDAEMONS="${SLURM1}${CR}${SLURM2}${CR}" \
        perl -i.orig -pe 's[(\s*exit\s+0\s*)\n*$][$ENV{SLURMDAEMONS}$1]s' \
        /etc/rc.local 
  else
    warn SLURM_START
    return
  fi

  [ $? -eq 0 ] || warn SLURM_INSTALL
}

# ----------- main ---------------

f_munge_build           || exit $?

f_munge_user_install    || exit $?

f_munge_start           || exit $?

f_munge_daemon_persist  || exit $?

f_slurm_build           || exit $?

f_slurm_config          || exit $?

f_slurm_install         || exit $?        
