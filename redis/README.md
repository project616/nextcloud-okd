REDIS COMPONENT DOC
====

Index
===
1. The Design
2. The ImageStream and buildconfig section
3. Pods and Replication Controller
4. The cluster management (Redis-trib)
5. Bootstrap the cluster
6. Add master/slave to the existing cluster


Bootstrap the cluster
===
The redis-trib pod coming from the redis-mgmt buildconfig described above represents the management pod used to run the redis-trib script in order to configure in the
correct way the cluster.
In particular, sending the command:

    kubectl exec -it redis-trib-64cnj -- redis-trib create --replicas 1 $(kubectl get pods -l app=redis-cluster -o jsonpath='{range.items[*]}{.status.podIP}:6379 ')

you exec the redis-trib script in the redis-mgmt pod bootstrapping the redis cluster.
