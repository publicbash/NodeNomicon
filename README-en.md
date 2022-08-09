# NodeNomicon

[Spanish Version](README.md)

```
--------------------------------------------------------------------------------

           ▄  ████▄ ██▄  ▄███▄     ▄  ████▄ █▀▄▀█ ▄█ ▄█▄   ████▄   ▄
            █ █   █ █  █ █▀   ▀     █ █   █ █ █ █ ██ █▀ ▀▄ █   █    █
        ██   ██   █ █  █.██▄▄~~~██-._██ _.█-█~▄~█-██.█_  ▀ █   ███   █
        █ █  █▀████ █//█ █▄   ▄▀█ █  █▀████ █   █ ▐█ █▄\ ▄▀▀█████ █  █
        █  █ █      ███▀ ▀███▀  █  █ █|        █   ▐ ▀███▀      █  █ █
        █   ██     //           █   ██|       ▀         \\      █   ██
        █         //__...--~~~~~~-._  |  _.-~~~~~~--...__\\     █
         ▀       //__.....----~~~~._\ | /_.~~~~----.....__\\     ▀
                 ===================\\|//===================
                                    `---`
--------------------------------------------------------------------------------
 NodeNomicon 0.7.8 beta
--------------------------------------------------------------------------------
```

By Dex0r & Kaleb for [OpenBASH](https://www.openbash.com/).

## Intro

It's a fact that infrastructure analysis is one of the fundamental pillars of computer security; hence the phrase that says: *a pentesting is as good as its information gathering*. Consequently, using [Nmap](https://nmap.org/) to perform port scanning is as necessary as the Swiss Knife was to MacGyver.

But not everything is happiness along the digital meadows, since there are no silver bullets in cybersecurity: analysts work with a plethora of tools to achieve valuable results. How many times has happened to you, dear analyst, that the tool you use does *almost* what you need? In [OpenBASH](https://www.openbash.com/) we frequently run into firewalls and filters during recognition tasks, without counting the cases where the size of the analyzed infrastructure is such that it leads us to limit the port scan, both in amplitude and depth, due to the immense amount of time required. This has motivated us to think *outside the box*, tinkering with solutions that provide acceptable results with the least possible cost of time and money, and that can also be integrated into analysis flows over large surfaces and with robust security measures.

And so, after smashing the keyboard for a long time, we have created the **NodeNomicon**.

## What is the NodeNomicon?

The **NodeNomicon** is a port scanning tool with the following features:

+ **Distributed**: Distribute the analysis in multiple cloud services and online virtualization.
+ **Extensible**: Using a *driver* model, can consume almost any cloud and virtualization service.
+ **Stealth**: Manage a swarm of nodes that share the workload, avoiding firewalls and security measures. You can consume APIs via [tor](https://www.torproject.org/) between the client and the cloud service provider.
+ **Fast**: In highly distributed workloads, it can perform extensive reconnaissance tasks in a short time.
+ **Inexpensive**: With a minimum cost and maximum use of resources, it generates professional quality results.
+ **Robust**: It is based on [Nmap](https://nmap.org/), with all the capacity and power that this entails.
+ **Versatile**: Highly parameterizable, both in its execution and configuration.
+ **Simple**: Developed almost entirely in [GNU Bash](https://www.gnu.org/software/bash/), requires only libraries and tools found in any Linux distribution, with the ability to use its [Docker](https://www.docker.com/) version for a simple, out-of-the-box *deploy*.
+ **Adaptable**: It is executed by command line to be able to be used in *headless* environments.
+ **Free**: Not convinced by its operation? Do you think you could improve it? You have the code at your disposal to modify it as you see fit.

### How does it work?

The standard **NodeNomicon** workflow mainly consists of three stages: target randomization, *worker* node management loop, and finally the compilation of results.

#### 1st Stage: Target Randomization

Generally, during a port scan, there is a set of IP addresses and ports to be scanned. A socket (the IP:Port pair) is considered to be the target for analysis. Therefore, to obtain the complete set of targets, the Cartesian product is performed between the target IP addresses (hosts) against the target ports, for example:

![Producto Cartesiano](/docs/imgs/fig_01_cartesian_product.png "Producto Cartesiano")

Once the Cartesian product is obtained, the result is *shuffled* through a randomization process. This random result is then divided by the total number of specified *worker* nodes, as follows:

![Carga de Trabajo](/docs/imgs/fig_02_workload.png "Carga de Trabajo")

Once the workload is obtained, a process optimizes it so can be *digested* more easily by [Nmap](https://nmap.org/). With all the workload distributed and ready to be processed, the analysis is executed between the worker nodes.

#### 2nd Stage: Node management loop

During this stage, the tool prepares an execution queue for all the workload, and based on the cloud services available within the *configuration pool*, it will create *worker* nodes, assigning a workload to each one and putting them to work.

![Multi-Cloud](/docs/imgs/fig_03_multicloud.png "Multi-Cloud")

Each cloud service is highly configurable, being able to establish the maximum amount of *slots* available to host nodes, the regions worldwide where the nodes will be created, the type of image to instantiate (Linux distribution or *snapshot*), etcetera. In addition, these configurations are grouped into *pools* allowing to manage profiles that are adjusted to the different types of analysis.

The load on each cloud service is distributed randomly, and if it is not available due to failure or saturation, the tool starts a *round robin* process to allocate a working node in one of the other available cloud services. In case that there's no availability, the node will wait at the queue until a *slot* is released.

Each created node receives a *payload* that configures it and prepares it to receive the workload. Once ready, the node launches an instance of [Nmap](https://nmap.org/) and it's monitored until its work is done. At the end, the node delivers the obtained results and gets deleted, freeing a *slot* for that cloud provider.

While this process is taking place, partial reports are generated in a .json file that can be monitored for a more user-friendly follow-up of the process; an HTML + JS viewer accompanies the tool to facilitate the task of the analyst.

#### 3rd Stage: Compilation of results

Once all nodes have finished their workload and there are no more pending batches, the tool gathers all the partial results to generate a single one in different formats as allowed by [Nmap](https://nmap.org/) (.nmap, .gnmap and .xml).

Taking into account the micro-cost capacity of cloud and virtualization service providers, at the end of the process a reconnaissance task will have been carried out from different IP addresses, with *random* objectives and at a minimum cost (in general, it is usually less than 1 cent of dollar per hour of work of each node).

## Supported Cloud Services

The drivers currently available for cloud services are:

+ [Digital Ocean](https://www.digitalocean.com/)
+ [Linode](https://www.linode.com/)
+ [Vultr](https://www.vultr.com/)

## But why?

The best sentence that summarizes this project arises during a black coffee morning, starting with the phrase:

> *Today is a good day to do science... isn't it?*
>
> *Yes, that's right.*

We like science. We like to experiment. We love to theorize and then see how far we get. We have a weakness for launching a process and then scrutinizing the results. And beyond the development of the project and its vicissitudes, we love to investigate; that's why, as *nerds* that we are, we want to spread the same enthusiasm to our colleagues, sharing with the community a tool that is essentially a *proof of concept*, knowing that the effort will have a return more than welcome.

Quote, space, hyphen, hyphen. :wink: