#!/bin/bash -x
# PURPOSE: Use Native Memory Tracking to monitor Java memory.
#          Logs are written to $JENKINS_HOME/logs which much exist.
#          HeapDump is written to $JENKINS_HOME/support (because it may contain sensitive data)
#
# ENVIRONMENT EXPECTED:
#   JENKINS_CLUSTER_ID: the "name" of this jenkins master.
#   WORKSPACE: Jenkins workspace path
#   JENKINS_HOME: Path to the root of jenkins
#   MAX_INTERNAL: KB limit after which a Heapdump will be collected.
#
# Required tools:
#   bash (gnu 4+)
#   date (with Gnu format support)
#   grep
#   java
#   jcmd
#   jstat
#   pgrep
#   ps
#   tail 
#   tr

TSTAMP="$(date +'%Y%m%d_%H%M%S')"


jenkinsPid="$(jps |grep -v Jps | cut -f1 -d' ')"
theLogDir="$JENKINS_HOME/logs"
supportDir="$JENKINS_HOME/support"

theLog="${JENKINS_CLUSTER_ID}.nmt.log"
theOldLog="${JENKINS_CLUSTER_ID}.nmt.old.log"

cd $theLogDir
  echo $TSTAMP $JENKINS_CLUSTER_ID >> $theLog
  
  jcmd $jenkinsPid VM.native_memory summary.diff  >> $theLog

  # See if we already have a baseline
  if tail -n10 $theLog | grep -q 'No baseline'; 
  then
    # Start a new log, new baseline.
    rm -f  $theOldLog
    mv  $theLog $theOldLog
    
    # Capture the current java information, too.
    echo $TSTAMP $JENKINS_CLUSTER_ID $(ps fp $jenkinsPid) > $theLog
    java -version >> $theLog
    
  
    jcmd $jenkinsPid VM.native_memory baseline  >> $theLog    
  fi
  
  # A way to find the last Internal size from the log above.
  # If something is not in there, set displays the current env... so redirect to null.
  # Only look in the last 20 lines, so we don't see an old entry that has long since passed.
  # After this operation $1='Internal', $2='Reserved', $3=SIZE of reserved. $4=delta size. ...
  set $(tail -n20 $theLog  | grep --line-buffered -m 1 '   Internal (' | tr '(=KB' ' ') > /dev/null

  # If bigger than MAX_INTERNAL (1GB by default)
  tooBig=${MAX_INTERNAL:-1000000}
  if [ 0$3 -gt $tooBig ]
  then
        # Internal size is TOO big... generate a heapdump.
        jcmd $jenkinsPid GC.heap_dump ${supportDir}/${TSTAMP}_${JENKINS_CLUSTER_ID}_heapdump.hprof >> $theLog
        echo "CREATED: ${supportDir}/${TSTAMP}_${JENKINS_CLUSTER_ID}_heapdump.hprof" >> $theLog
        echo "${supportDir}/${TSTAMP}_${JENKINS_CLUSTER_ID}_heapdump.hprof" >> ${WORKSPACE}/HeapDump.log
  fi
  
  # Capture logs 
  echo $TSTAMP $JENKINS_CLUSTER_ID > ${JENKINS_CLUSTER_ID}_GC_metaspace.log 
  echo $TSTAMP $JENKINS_CLUSTER_ID > ${JENKINS_CLUSTER_ID}_GC_class_output.log  
  jstat -gc ${jenkinsPid} >> ${JENKINS_CLUSTER_ID}_GC_metaspace.log 
  jcmd ${jenkinsPid} GC.class_stats >> ${JENKINS_CLUSTER_ID}_GC_class_output.log

cd $WORKSPACE
