#!/bin/bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

usage () {
  echo "Usage:"
  echo "    ./e2e/e2e-cloud.sh -h Display this help message."
  echo "    ./e2e/e2e-cloud.sh -m <master-url> -r <spark-repo> -i <image-repo>"
  echo "        note that you must have kubectl configured to access the specified"
  echo "        <master-url>. Also you must have access to the <image-repo>. "
}

### Basic Validation ###
if [ ! -d "integration-test" ]; then
  echo "This script must be invoked from the top-level directory of the integration-tests repository"
  usage
  exit 1
fi

### Set sensible defaults ###
REPO="https://github.com/apache/spark"
IMAGE_REPO="docker.io/kubespark"

### Parse options ###
while getopts m:r:i:h option
do
 case "${option}"
 in
 h)
  usage
  exit 0
  ;;
 m) MASTER=${OPTARG};;
 r) REPO=${OPTARG};;
 i) IMAGE_REPO=${OPTARG};;
 \? )
 echo "Invalid Option: -$OPTARG" 1>&2
 exit 1
 ;;
 esac
done

### Ensure cluster is set.
if [ -z "$MASTER" ]
then
   echo "Missing master-url (-m) argument."
   echo ""
   usage
   exit
fi

echo "Running tests on cluster $MASTER against $REPO."
echo "Spark images will be created in $IMAGE_REPO"

set -ex
root=$(pwd)

# clone spark distribution if needed.
if [ -d "spark" ];
then
  (cd spark && git pull);
else
  git clone $REPO;
fi

cd spark && ./dev/make-distribution.sh --tgz -Phadoop-2.7 -Pkubernetes -DskipTests
tag=$(git rev-parse HEAD | cut -c -6)
echo "Spark distribution built at SHA $tag"

cd dist && ./sbin/build-push-docker-images.sh -r $IMAGE_REPO -t $tag build
if  [[ $IMAGE_REPO == gcr.io* ]] ;
then
  gcloud docker -- push $IMAGE_REPO/spark-driver:$tag && \
  gcloud docker -- push $IMAGE_REPO/spark-executor:$tag && \
  gcloud docker -- push $IMAGE_REPO/spark-init:$tag
else
  ./sbin/build-push-docker-images.sh -r $IMAGE_REPO -t $tag push
fi

cd $root/integration-test
$root/spark/build/mvn clean -Ddownload.plugin.skip=true integration-test \
          -Dspark-distro-tgz=$root/spark/*.tgz \
          -DextraScalaTestArgs="-Dspark.kubernetes.test.master=k8s://$MASTER \
            -Dspark.docker.test.driverImage=$IMAGE_REPO/spark-driver:$tag \
            -Dspark.docker.test.executorImage=$IMAGE_REPO/spark-executor:$tag" || :

echo "TEST SUITE FINISHED"