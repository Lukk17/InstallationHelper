# Orchestrator image for unattended scenario queues.
#
# This exists because a queue driven from an interactive shell is not a queue. A previous run
# finished batch one at 04:00 and batch two never started, because the next launch depended on
# a human or an agent being awake to react. The playbook already solved the same problem by
# running detached inside its container. This applies that to the scheduler itself: the queue
# runs inside a container of its own, so it survives every shell, disconnect and session that
# started it.
#
# It talks to the host Docker daemon through the mounted socket rather than nesting Docker, so
# the scenario containers it starts are siblings on the same daemon and behave exactly as they
# do when launched by hand.
FROM docker:28-cli

# run.sh and container.sh are bash, not POSIX sh, and use mapfile plus associative arrays.
# The GNU tools matter too: busybox sed does not handle every -E expression these scripts use,
# and a silently different sed would corrupt a generated variable file rather than fail loudly.
RUN apk add --no-cache \
        bash \
        grep \
        sed \
        gawk \
        coreutils \
        procps \
        curl

WORKDIR /repo

# No CMD on purpose. The caller passes the exact run.sh invocation, which keeps the queue
# definition visible in the docker run command and in `docker inspect` afterwards, rather than
# baked into an image where nobody can see what was actually queued.
ENTRYPOINT ["/bin/bash"]
