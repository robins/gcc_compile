This script helps to maintain an upto date `gcc` binary, while trying to cause minimal disruption to on-going compilations that may be using gcc. (At this point, it only looks for postgres buildfarm compilations, but you can add your own checks too). 

This `README` file has some helpful steps / samples towards achieving that.

Install GCC (once)
------------------
- `git clone https://github.com/gcc-mirror/gcc.git`
- If that fails (bad network could do that), sometimes cloning from gcc-mirror worked for me.
  - `git clone git://gcc.gnu.org/git/gcc.git`

Prerequisites - Compulsory
-------------------------
Installation command (Debian based): `sudo apt install libmpfr-dev libmpc-dev`
OR
Installation command (CentOS based): `sudo yum install mpfr-devel libmpf-devel`


Prerequisites - Optional
------------------------

Installation command (Debian based): `sudo apt install libgcc-13-dev texinfo m4 expect python3-pip`
OR
Installation command (CentOS based): `sudo yum install texinfo m4 expect python3-pip`

`runtest` would be good too (for which you may need `python3-pip` first - `sudo apt install python3-pip runtest` or `sudo yum install python3-pip runtest` )

----

Sample Log - No-Op
------------------
Log from a simple run, where the script checked and didn't fine any updates to the `gcc` git repository.
```
gcsfda9 20250121_1930 - git checkout successful.
gcsfda9 20250121_1930 - git pull successful.
gcsfda9 20250121_1930 - No change in gcc version. Quitting.
```
Sample Log - Rebuild - Quick Run
--------------------
Log from a run, where script found recent updates to git, and the compilation was quick (i.e. finished in ~1 min).
```
gcsd95e 20250121_1945 - git checkout successful.
gcsd95e 20250121_1945 - git pull successful.
gcsd95e 20250121_1945 - gcc has changed - [f31d49d6541] vs [f3d884da128]. Recompiling.
gcsd95e 20250121_1945 - make successful
gcsd95e 20250121_1946 - make install successful.
gcsd95e 20250121_1946 - Postgres Buildfarm process not running (0). Good.
gcsd95e 20250121_1946 - gcc version string has changed from [15.0.1 20250121 (experimental) - f31d49d6541] to [15.0.1 20250121 (experimental) - f3d884da128]
```

Sample Log - Rebuild worked, but waited for buildfarm runs to complete
---------------------------
Log from a run, where the script compiled `gcc` successfully but had to wait for concurrent postgres buildfarm process to finish, before swapping out the binaries.
```
gcs0b69 20250121_0830 - git checkout successful.
gcs0b69 20250121_0830 - git pull successful.
gcs0b69 20250121_0830 - gcc has changed - [5cd4605141b] vs [64a162d5562]. Recompiling.
gcs0b69 20250121_0830 - make successful
gcs0b69 20250121_0831 - make install successful.
gcs0b69 20250121_0831 - Postgres Buildfarm process running (2)
gcs0b69 20250121_0831 - Postgres Buildfarm process running (2)
gcs0b69 20250121_0831 - Postgres Buildfarm process running (2)
gcs0b69 20250121_0832 - Postgres Buildfarm process running (2)
gcs0b69 20250121_0832 - Postgres Buildfarm process not running (0). Good.
gcs0b69 20250121_0832 - gcc version string has changed from [15.0.1 20250120 (experimental) - 5cd4605141b] to [15.0.1 20250120 (experimental) - 64a162d5562]
```

Sample Log - Rebuild worked, but took hours
-------------------------------------------
Log from a run, where git updates were found, but the `gcc` compilation took hours.
```
gcs2215 20250120_1100 - git checkout successful.
gcs2215 20250120_1100 - git pull successful.
gcs2215 20250120_1100 - gcc has changed - [9d4b1e37725] vs [a7185d9bc6d]. Recompiling.
gcs2215 20250120_1259 - make successful
gcs2215 20250120_1300 - make install successful.
gcs2215 20250120_1300 - Postgres Buildfarm process not running (0). Good.
gcs2215 20250120_1300 - gcc version string has changed from [15.0.1 20250119 (experimental) - 9d4b1e37725] to [15.0.1 20250120 (experimental) - a7185d9bc6d]
```

Sample Log - Rebuild failed, but fresh configure / make worked
--------------------------------------------------------------
Log from a run, where the first compilation attempt failed, but a fresh compilation effort succeeded.
```
gcsdea1 20241009_2300 - git checkout successful.
gcsdea1 20241009_2300 - git pull successful.
gcsdea1 20241009_2300 - gcc has changed - [41179a32768] vs [cf08dd297ca]. Recompiling.
gcsdea1 20241010_0017 - Unable to make.
gcsdea1 20241010_0017 - configure successful.
gcsdea1 20241010_0153 - make distclean + make successful
gcsdea1 20241010_0153 - make install successful.
gcsdea1 20241010_0153 - gcc version string has changed from [15.0.0 20241009 (experimental) - 41179a32768] to [15.0.0 20241009 (experimental) - cf08dd297ca]
```

Sample Log - Skip if the instance is already over-burdened
----------------------------------------------------------
Log from a run (between two No-Op runs), where the script immediately bailed, when CPU was very high.
```
gcs5b0d 20250124_0400 - git checkout successful.
gcs5b0d 20250124_0400 - git pull successful.
gcs5b0d 20250124_0400 - No change in gcc version. Quitting.

gcs1750 20250124_0415 - High CPU 1-min ratio (14). Aborting.

gcsa97a 20250124_0430 - git checkout successful.
gcsa97a 20250124_0430 - git pull successful.
gcsa97a 20250124_0430 - No change in gcc version. Quitting.
```