@echo off
cd %~dp0
echo ----Martin's Server Launcher Script by TX----
java --add-modules=jdk.incubator.vector -Xms4G -Xmx4G -XX:+UnlockExperimentalVMOptions -XX:+UseZGC -XX:+ZGenerational -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:-ZUncommit -XX:+ParallelRefProcEnabled -XX:ZAllocationSpikeTolerance=12 -DLeaf.enableFMA -jar server.jar --nogui
pause