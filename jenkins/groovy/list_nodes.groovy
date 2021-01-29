// use with jenkins-cli.sh scripting
// $XLRINFRA/bin/jenkins-cli.sh groovysh < list_nodes.groovy | grep ^NODE_ONLINE

import hudson.FilePath
import hudson.model.Node
import hudson.model.Slave
import jenkins.model.Jenkins

Jenkins jenkins = Jenkins.instance
println ""
for (Node node in jenkins.nodes) {
  if (!node.toComputer().online) {
    print "\nNODE_OFFLINE=$node.nodeName"
    continue
  }
  print "\nNODE_ONLINE=$node.nodeName"
}
println ""
