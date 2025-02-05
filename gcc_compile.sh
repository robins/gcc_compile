#!/bin/bash

# This is a primitive version I use to compile GCC for the Postgres buildfarm
# Good chances you'd need to modify this, to suit your needs.

# On a few conditions (1) The script compile `gcc` successfully and
# (2) when concurrent usage is not found, we swap out the recently built
# gcc binary folder with the one in use.

# Here we set defaults for all environments, and...
gccbasedir="/opt/gcc"

# Trying to use all available CPUs, and then one.
vcpu=$(( `nproc`+1 ))

# # ... and then, we override those defaults if required, for a specific environemnt
# update_dirs_if_pi() {
#   unm=`uname -a`
#   if [[ "${unm,,}" == *"pi4"* ]]; then
#     echo "Updating dirs for pi"
#     gccbasedir="/media/pi/250gb/proj/gcc"
#     vcpu=$(( `nproc`-1 ))
#   fi
# }

# update_dirs_if_pi

srcdir="${gccbasedir}/source"
objdir="${gccbasedir}/objdir"
tgtdir="${gccbasedir}/target"
proddir="${gccbasedir}/prod"

buildlog=${gccbasedir}/build.log
compilelog=${gccbasedir}/compile.log

# We try to wrap up to the same directory, where we started from
startdir=`pwd`

# We generate a unique hash for this run, so that we can identify the logs
thiscommand='gcs' # GCC Compile script
hash=`openssl rand -hex 2`
decho () {
  t=`date "+%Y%m%d_%H%M"`
  while IFS= read -r line
  do
    echo "${thiscommand}${hash} ${t} - ${line}" | tee -a ${buildlog}
  done <<< "$1"
}

# Ensure all directories exist, or bail
mkdir -pv ${objdir} || { decho "Unable to ensure $objdir exists. Quitting."; wrap_up_before_exit; exit 1; }
mkdir -pv ${tgtdir} || { decho "Unable to ensure $tgtdir exists. Quitting."; wrap_up_before_exit; exit 1; }
mkdir -pv ${proddir} || { decho "Unable to ensure $proddir exists. Quitting."; wrap_up_before_exit; exit 1; }

if [ ! -d ${srcdir} ]; then
  decho "Source folder doesn't exist"
  mkdir -pv ${srcdir} || { decho "Unable to ensure $srcdir exists. Quitting."; wrap_up_before_exit; exit 1; }
  git clone https://github.com/gcc-mirror/gcc.git || { decho "Unable to do git clone. Quitting."; wrap_up_before_exit; exit 1; }
fi


get_gcc_version() {
  echo `${proddir}/bin/gcc --version | head -1 | awk '{print $3 " " $4 " " $5}'`
}

recompile_if_so_recommended() {
  
  cd $objdir

  # Earlier we used to check if the failure explicitly requests a 'make distclean'.
  # But sometimes the failure doesn't say so, and the solution is to the same SOP
  # So might as well do a make distclean anyway

  #e=`cat ${compilelog} | grep run | grep "make distclean" | grep error | wc -l`
  #if [ $e -ge 0 ]; then
    
    # Sometimes compilation fails with this message:
    # configure: error: in `/home/robins/proj/gcc/objdir/libcc1':
    # configure: error: changes in the environment can compromise the build
    # configure: error: run `make distclean' and/or `rm ./config.cache' and start over
    # decho "make distclean / rm config.cache recommended. Retrying"

    make distclean && decho "make distclean successful" || decho "make distclean unsuccessful"
    find ${objdir} -type f -name config.cache | grep objdir | xargs -P1 -i rm -v {}

    #confflags="--disable-gcov --disable-bootstrap --disable-nls --disable-lto --disable-multilib --prefix=${tgtdir}"
    confflags="--prefix=${tgtdir} --disable-multilib"
    ${srcdir}/configure ${confflags} &>> $compilelog 
    r="$?" 
    if [ "$r" -eq "0" ]; then
      decho "configure successful."
    else
      decho "configure unsuccessful."
      return $r
    fi
    make -j${vcpu} &>> $compilelog 
    r="$?" 
    if [ "$r" -eq "0" ]; then
      decho "make (retry) successful"
    else
      decho "make (retry) unsuccessful"
      return $r
    fi
  # else
  #   decho "didn't try recompiling, since not recommended during make" 
  #   r=111
  # fi

  return $r
}

reset_git_commit() {
  # revert git commit to what we found when starting
  if [ "${gcc_commit_new}" != "${gcc_commit_revert_to_before_exit}" ]; then
    cd ${srcdir}
    git checkout ${gcc_commit_revert_to_before_exit} && decho "git switched back to $gcc_commit_revert_to_before_exit."    || decho "### Unable to switch git back ###."
  fi
}

wrap_up_before_exit() {
  reset_git_commit
  cd $startdir
}


## Doing basic pre-checks before we begin
## ======================================

pidof -o %PPID -x $0 >/dev/null && echo "Looks like a previous run of script '$0' is still active. Aborting." && exit 1
# # Abort, if a previous run is still running
# s="prev-gcc"
# n=`ps -ef | grep "$s" | grep -v grep | wc -l`
# if [[ "$n" -ge 1 ]]; then
#   decho "Looks like a previous run is still active - $n processes found using '$s'. Aborting."
#   exit 1
# else
#   # Empty out compile.log
#   echo "" > ${compilelog}
# fi

# Abort recompiling GCC, if the system is already under stress
loadavg=$(echo "scale=0; `cat /proc/loadavg | awk '{print $1}' `/1"| bc)
if [ "$loadavg" -gt `nproc` ]; then
  decho "High CPU 1-min ratio ($loadavg). Aborting."
  exit 0
# else
#   decho "CPU 1-min ratio ($loadavg) is okay. Proceeding."
fi

wait_till_buildfarm_processes_quit() {
  # If a buildfarm run is happening, wait till it finishes
  while true
  do
    r="`pidof -x "run_branches.pl" | tr ' ' '\n' | wc -l`"
    if [[ "${r}" -eq 0 ]]; then
      decho "Postgres Buildfarm process not running (${r}). Good."
      break
    fi
    decho "Postgres Buildfarm process running (${r})"
    sleep $(( $RANDOM / 500 )) || sleep 300
  done
}


## OK. All checks are good. Now start building GCC
## ===============================================

# Not using decho, since we don't need timestamp for a blank line
echo >> ${buildlog}

cd $srcdir

git_commit_provided=$1
gcc_version_old=`get_gcc_version`
gcc_commit_old=`git rev-parse --short HEAD`
gcc_commit_revert_to_before_exit=$gcc_commit_old

bf_gcc_version_old="${gcc_version_old} - ${gcc_commit_old}"

# This is a local git operation
git checkout master                              && decho "git checkout successful."    || { decho "Unable to checkout git. Is repository in place? Quitting." ; wrap_up_before_exit; exit 1; }

if [[ $git_commit_provided != "" ]]; then
  git checkout $git_commit_provided               && decho "git checkout successful."    || { decho "Unable to checkout commit provided. Is it a valid commit id? Quitting." ; wrap_up_before_exit; exit 1; }
else
  # This (on the other hand), is a network operation
  git pull                                        && decho "git pull successful."        || { decho "Unable to git pull. Are we connected? Quitting." ; wrap_up_before_exit; exit 1; }
fi

gcc_commit_new=`git rev-parse --short HEAD`

if [ "$gcc_commit_old" != "$gcc_commit_new" ]; then

    decho "gcc has changed - [$gcc_commit_old] vs [$gcc_commit_new]. Recompiling."
    
    # Cleanup existing objdir / target folders, if it exists
    cd $gccbasedir
    #[ -d "${gccbasedir}/objdir" ] && rm -rf ${gccbasedir}/objdir || echo "Unable to delete ${gccbasedir}/objdir dir, but that's okay. Continuing."
    #[ -d "${gccbasedir}/target" ] && rm -rf ${gccbasedir}/target || echo "Unable to delete ${gccbasedir}/target dir, but that's okay. Continuing."

    mkdir -pv ${objdir} || { decho "Unable to ensure $objdir exists. Quitting."; wrap_up_before_exit; exit 1; }
    mkdir -pv ${tgtdir} || { decho "Unable to ensure $tgtdir exists. Quitting."; wrap_up_before_exit; exit 1; }

    # Recompile gcc - could take upwards of 6+ hours
    cd $objdir

    #${srcdir}/configure ${confflags}   && decho "configure successful."       || { decho "Unable to configure. Quitting.";  wrap_up_before_exit;  exit 1; }

    nice -n 20 make -j${vcpu} &>> $compilelog 
    if [ "$?" -eq "0" ]; then
      decho "make successful"
    else
      decho "Unable to make."; 
      recompile_if_so_recommended || { decho "Unable to make. Quitting. "; wrap_up_before_exit;  exit 1; }
    fi

    # This install everything to a temporary location (tgtdir) - before swapping out to prod binaries.
    make install                       && decho "make install successful."    || { decho "Unable to make install. Quitting."; reset_git_commit; exit 1; }

    wait_till_buildfarm_processes_quit

    # This logic does a (near) atomic swap of folders
    # Move prod -> prod_old and if successful move recently built binaries to prod. if both succeed, then remove prod_old.
    #   However, if the above fails, then reinstate the previously in-use binaries back to prod.
    (mv ${proddir} ${proddir}_old && mv ${tgtdir} ${proddir}) && rm -r ${proddir}_old || (test -d ${proddir} || mv ${proddir}_old ${proddir})
  
    gcc_version_new=`get_gcc_version`
    bf_gcc_version_new="${gcc_version_new} - ${gcc_commit_new}"

    decho "gcc version string has changed from [$bf_gcc_version_old] to [$bf_gcc_version_new]"
    gcc_commit_revert_to_before_exit=$gcc_commit_new
    # /media/pi/250gb/proj/bf/v17/update_personality.pl --config=/media/pi/250gb/proj/bf/v17/build-farm.conf.extensive --compiler-version="${bf_gcc_version_new}" && decho "Update buildfarm personality successful."    || { decho "Unable to update buildfarm personality. Quitting.";  wrap_up_before_exit; exit 1; }

else
    decho "No change in gcc version (${gcc_commit_new}). Quitting."
fi

wrap_up_before_exit
exit 0