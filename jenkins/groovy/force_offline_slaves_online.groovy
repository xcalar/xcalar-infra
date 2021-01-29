import hudson.model.*
import jenkins.model.Jenkins
import org.jvnet.jenkins.plugins.nodelabelparameter.*
import org.jvnet.jenkins.plugins.nodelabelparameter.node.*

Jenkins jenkins = Jenkins.instance
def jenkinsNodes = jenkins.nodes

def excludedNodes = ["edison2", "edison3", "feynman", "jenkins-slave0", "jenkins-slave1"]

for (Node node in jenkinsNodes) {
    if (!excludedNodes.contains(node.name)) {
        computer = node.getComputer()

        if (computer.isOffline()) {
            offlineCause = computer.getOfflineCause()
            if (offlineCause) {
                duration = System.currentTimeMillis() - offlineCause.getTimestamp()
                duration = duration / (1000 * 60 * 60)
                println node.name + " is offline for " + duration.toString() + " hrs."
                if (duration > 36) {
                    println "Forcing " + node.name + " online."
                    computer.cliOnline()
                }
            }
        }
    }
}
