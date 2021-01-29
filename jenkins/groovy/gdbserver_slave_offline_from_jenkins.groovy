import hudson.model.*
import jenkins.model.Jenkins
import org.jvnet.jenkins.plugins.nodelabelparameter.*
import org.jvnet.jenkins.plugins.nodelabelparameter.node.*
import hudson.util.RemotingDiagnostics
import hudson.slaves.EnvironmentVariablesNodeProperty

instance = Jenkins.getInstance()
build = Thread.currentThread().executable
workspace = build.getWorkspace()

if (workspace) {
    slave = workspace.toComputer()
    channel = workspace.getChannel()
    gdbserver = 'def proc = "pgrep gdbserver".execute(); proc.waitFor(); println proc.in.text'

    result = RemotingDiagnostics.executeGroovy(gdbserver, channel)

    // For some reason executeGroovy returns space when it can't find gdbserver
    if (result.size() > 2) {
        println slave.name + " is running gdbserver."
        println "Taking it offline."

        slave.cliOffline("gdbserver is running")
    }

    node = instance.getNode(slave.name)
    props = node.nodeProperties.getAll(hudson.slaves.EnvironmentVariablesNodeProperty.class)

    if(props.empty) {
        if (result.size() > 2) {
            def entry = new EnvironmentVariablesNodeProperty.Entry("GDBSERVER", "gdbserver is running." + slave.name + " is offline.")
        } else {
            def entry = new EnvironmentVariablesNodeProperty.Entry("GDBSERVER", "")
        }

        try {
            node.nodeProperties.add(entry)
        } catch(Exception ex) {
            println "Caught exception"
        }

    } else {
        if (result.size() > 2) {
            for (prop in props) {
                prop.envVars.put("GDBSERVER", "gdbserver is running.")
            }
        } else {
            for (prop in props) {
                prop.envVars.put("GDBSERVER", "")
            }
        }
    }
}
