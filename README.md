NEXTCLOUD OKD PROJECT
===

This goal of this project is to create a reference architecture to deploy a highly configurable,
scalable, stateless nextcloud installation on top of Openshift Origin.
It is a first prototype, but the provided configuration reflects the following requirements:

* Having a LDAP or an auth mechanism different from the local authentication
* Using an external primary storage, such us S3
* Making the nextcloud instance stateless, with a dynamic config.php that download datas from
an etcd pod
* Using an external database cluster (such as galera with a maxscale load balancing tier)

ETCD CONFIG STRUCTURE
---

The ETCD nextcloud configuration structure looks like the following tree:

    nextcloud/
        config/
            data_directory/
            asset_directory/
            apps_directory/
            s3/
                /s3_endpoint/
                /s3_port/
                /bucket_name/
                /access_key/
                /secret_key/

In the structure above, each dir represents a node that can contain a value (LEAF NODE) or a child.
Assuming that this is the default config, we can start getting values in a deep search fashion.

STEP 0 - CREATE THE ETCD INITIAL STRUCTURE
---

Inside the $PWD/scripts section an **etcd-cli.go** golang script is provided to help interacting users with the Application etcd service (that you can find its proper namespace) that is routed at:

    http://etcd.<YOURDOMAIN>

To check if it's working properly, try to make a curl on the *health* key or use the classic *etcdctl* cli to make some queries.
To register or modify on the etcd the nextcloud keys with new configuration values, you can just edit the **nextcloudrc** ini file provided and run the script: in this way the *start_nextcloud_script*
will be able to substitute the retrieved/current values, given more flexibility to the stateless nextcloud installation because we can push the new configuration each time we need to do it.
Starting from this point, the basic template of the **config.php** nextcloud configuration file looks like the following:

        <?php
          $CONFIG = array (
          "log_type" => "syslog",
          //"datadirectory" => '{{ data_directory }}',
          "updatechecker" => false,
          "check_for_working_htaccess" => false,
          "asset-pipeline.enabled" => false,
          //"assetdirectory" => '{{ asset_directory }}',

          "apps_paths" => array(
             0 =>
              array (
                  'path'=> '{{ apps_directory }}',
                  'url' => '/apps',
                  'writable' => true,
              ),
              1 =>
              array (
                  'path' => '{{ apps_directory }}',
                  'url' => '/apps-appstore',
                  'writable' => true,
              ),
            ),

          'objectstore' => array(
          'class' => 'OC\Files\ObjectStore\S3',
          'arguments' => array(
              'bucket' => '{{ bucket_name }}',
              'autocreate' => true,
              'key'    => '{{ accesskey }}',
              'secret' => '{{ secretkey }}',
              'hostname' => '{{ s3_endpoint }}',
              'port' => '{{ s3_port }}',
              'use_ssl' => true,
              'region' => 'optional',
              // required for some non amazon s3 implementations
              'use_path_style'=> true
              ),
            )
         );

and the start script of the Pod just download from etcd the configuration values and replace them on the correct position given by the placeholders.

At this point, we can create the etcd environment to serve nextcloud keys just running:

    $ oc new-project etcd
    $ for i in $(ls ~/projects/openshift-apps/etcd/ | awk '/yml/ {print $0}'); do  oc create -f $i -n etcd; done


CREATE THE STAGING ENVIRONMENT
---

//The staging environment is built in a blue/green develpment fashion to allow users to avoid seeing the increasing
//number of projects and interactions between different stages

First of all you can choose the preferred deployment mechanism: 

* blue/green in a single stage
* rolling release throught 3 projects

The configuration is very flexible and you can choose what is the best approach to be used according to the pipelines developed and the instance configuration.


Blue/Green staging environment
---

First, you need to create all the needed configmaps, secrets and jenkins pipelines:

    $ oc create -f nextcloud_configmap.yml
    $ oc create -f modsecurity_configmap.yml
    $ oc create -f nextcloud_apache_mpm_configmap.yml
    $ oc create -f syslog_configmap.yml

Then, create the swiftrc secret to make all pods able to interact with swift (where plugins resides):

    $ oc create -f nextcloud_swiftrc_secret.yml


If you have a storageclass provided (in this case we call it crs-storage), you can create a PVC that can be attached to the nextcloud-{blue,green} pod:

    $ oc create -f nextcloud_volume.yml

The pvc created reflect this yml file:


    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      annotations:
        volume.beta.kubernetes.io/storage-provisioner: kubernetes.io/glusterfs
      name: nextcloud-data-volume
      namespace: nextcloud-staging
    spec:
      accessModes:
      - ReadWriteMany
      resources:
        requests:
          storage: 1500Gi
      storageClassName: crs-storage


Of course, users can customize the storage size, the storage class used and, on the
*deploymentConfig* side, users can set the /data mountpoint to **emptyDir**: in this case
the pvc creation can be skipped.
After the creation of all the objects described above, we can start to build the **imagestreams**:

    $ oc create -f nextcloud_buildconfig.yml

After the build is finished:

    $ oc new-app -f nextcloud_dc.yml

**TODO**: Put here the output



CREATE Q/A ENVIRONMENT
---

Despite we talk about blue/green deployment in the paragraph above, we can add two more stages to the application and using routes and tools 
like *istio* users can decide which services expose to the end users.
In this case we can create a Q/A namespace:

    $ oc new-project nextcloud-qa

    $ cd ${NEXTCLOUD_QA_NAMESPACE}
    $ oc create -f nextcloud_configmap.yml
    $ oc create -f modsecurity_configmap.yml
    $ oc create -f nextcloud_apache_mpm_configmap.yml
    $ oc create -f syslog_configmap.yml
    $ oc create -f nextcloud_configmap.yml
    $ oc create -f nextcloud_pipeline_qa.yml
    $ oc new-app -f nextcloud_dc.yml


Now we need to update the deploymentconfig trigger to make it sensitive to a new tag triggered by the new build on the **staging** namespace:

    $ oc set triggers dc/nextcloud-qa --from-image=nextcloud-qa/nextcloud-build:qa-ready -c nextcloud -n nextcloud-qa

One of the most important rules in this game is help jenkins to make everything automated: to do this we make it 
admin of the nextcloud-staging namespace, so it will have rights to view any resource in the project and modify 
any resource in the project except for quota.

    $ oc policy add-role-to-user admin system:serviceaccount:nextcloud-staging:jenkins -n nextcloud-staging

For the first time, during the init of the environment, we just need to trigger manually a new build like the following:

    $ oc start-build nextcloud-build -n nextcloud-staging

and then force manually the new tag to Q/A namespace running:

    $ oc tag nextcloud-staging/nextcloud-build:latest  nextcloud-qa/nextcloud-build:qa-ready


GO LIVE ON PRODUCTION ENVIRONMENT
---

Passing from the Q/A environment to the production one follows the same rules used to pass from the staging to the Q/A
environment, using triggers on the DeploymentConfig to create the new build.
Of course, the key of promoting images through stages remain jenkins pipelines, so it's really important to check the
quality of the pipelines because it reflects on your deployments from staging to production.

    $ oc new-project nextcloud-prod
    $ oc create -f nextcloud_configmap.yml
    $ oc new-app -f nextcloud_dc.yml

As said above, the production environment, like the previous one, is build by triggering the ImageChange/ConfigChange on the deploymentconfig 
and this is done using a specific image tag (in this case **prod-ready**).
To avoid errors related to the automation tool and the provided pipeline, after the test phase the user **MUST** trigger the rollout of the 
application throught a user input requested by the Jenkins pipeline that manage in depth the flow of the CI/CD from the dev namespace to the production one.
To make jenkins able to handle triggers on deploymentconfig and tag on ImageStream, we need to add the correct role to the Jenkins user (like we've done in the Staging => Q/A namespaces):

    $ oc policy add-role-to-user admin system:serviceaccount:nextcloud-qa:jenkins -n nextcloud-prod

Then explicitly enable the trigger on the dc:

    $ oc set triggers dc/nextcloud-prod --from-image=nextcloud-prod/nextcloud-build:prod-ready -c nextcloud -n nextcloud-prod

and finally like done before we can manually force the first deployment running:

    $ oc tag nextcloud-qa/nextcloud-build:qa-ready  nextcloud-prod/nextcloud-build:prod-ready

From now each phase is automated, except the Q/A pipeline that right now we need to start manually to prevent any kind of error because this 
represents the last section of the flow and end with the **rollout** of the application in production.

**TODO**: We're planning to make all the flaw completely automated but it implies some more checks.



NEXTCLOUD STANDALONE MODE
---

This section represents a quick start to make a quick nextcloud deployment.
The following is expecting you have a working minishift (or an okd working cluster) up & running.


    $ oc new-project nextcloud-standalone
    $ oc create -f nextcloud_configmap.yml
    $ oc create -f nextcloud_svc.yml
    $ oc create -f nextcloud_buildconfig.yml   # This will create the new imagestream
    $ oc new-app -f nextcloud_dc.yml



TIPS
===

Enable communication across pod services on different namespaces:

https://docs.openshift.com/container-platform/3.6/admin_guide/managing_networking.html#admin-guide-pod-network

oc adm pod-network join-projects --to=nextcloud-staging nextcloud-prod nextcloud-qa nextcloud-galera etcd

TODO
---
