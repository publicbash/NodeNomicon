# NodeNomicon

[English Version](README-en.md)

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

Por Dex0r y Kaleb, para [OpenBASH](https://www.openbash.com/).

## Intro

Es un hecho fáctico que el análisis de infraestructura es uno de los pilares fundamentales de la seguridad informática; de ahí la frase que reza: *un pentesting es tan bueno como su information gathering*. En consecuencia, utilizar [Nmap](https://nmap.org/) para llevar a cabo el escaneo de puertos es tan necesario como lo era la navaja suiza para MacGyver. 

Pero no todo es felicidad en las praderas digitales, ya que en ciberseguridad no existen las *balas de plata*: los analistas trabajan con una plétora de herramientas para conseguir resultados de valor. ¿Cuántas veces te ha sucedido, querido analista, que la herramienta que utilizas hace *casi* lo que necesitas? En [OpenBASH](https://www.openbash.com/) nos topamos frecuentemente con bloqueos y filtros durante las tareas de reconocimiento, sin contar los casos donde la envergadura de la infraestructura analizada es tal que nos lleva a acotar el escaneo de puertos, tanto en amplitud como en profundidad, debido a la inmensa cantidad de tiempo requerido. Esto nos ha motivado a pensar *fuera de la caja*, experimentando con la creación de soluciones que otorguen resultados aceptables con el menor costo de tiempo y dinero posible, y que además se puedan integrar en flujos de análisis hacia grandes superficies y con medidas de seguridad robustas.

Y es así qué tras azotar el teclado durante mucho tiempo, hemos creado al **NodeNomicon**.

## ¿Qué es el NodeNomicon?

El **NodeNomicon** es una herramienta de análisis de puertos con las siguientes características:

+ **Distribuido**: Reparte el análisis en múltiples servicios cloud y de virtualización online.
+ **Extensible**: Utilizando un modelo de *drivers*, le permite consumir casi cualquier servicio cloud y de virtualización.
+ **Furtivo**: Gestiona un enjambre de nodos que reparten la carga de trabajo, evitando bloqueos y medidas de seguridad. Puede consumir APIs vía [tor](https://www.torproject.org/) entre el cliente y el proveedor de servicio cloud.
+ **Veloz**: En cargas de trabajo de alta distribución, puede llevar a cabo tareas de reconocimiento extensas en tiempos acotados.
+ **Económico**: Con un costo mínimo y aprovechamiento máximo de los recursos, genera resultados de calidad profesional.
+ **Robusto**: Se basa en [Nmap](https://nmap.org/), con toda la capacidad y potencia que esto supone.
+ **Versátil**: Altamente parametrizable, tanto en su ejecución como configuración.
+ **Simple**: Desarrollado casi por completo en [GNU Bash](https://www.gnu.org/software/bash/), requiere solamente librerías y herramientas encontradas en cualquier distribución de Linux, con la posibilidad de utilizar su versión en [Docker](https://www.docker.com/) para un *deploy* simple y listo para usar.
+ **Adaptable**: Se ejecuta por línea de comandos para poder ser utilizado en entornos *headless*.
+ **Libre**: ¿No te convence su funcionamiento? ¿Te parece que podrías mejorarlo? Tienes el código a disposición para modificarlo a tu antojo.

### ¿Cómo funciona?

El flujo de trabajo estándar del **NodeNomicon** consta principalmente de tres etapas: aleatorización de objetivos, bucle de gestión de nodos *trabajadores* y finalmente la recopilación de los resultados. 

#### 1° Etapa: Aleatorización de objetivos

Generalmente durante un análisis de puertos se dispone de un conjunto de direcciones IP y puertos a analizar. Se considera que un socket (el par IP:Puerto) es un objetivo de análisis. Por ende, para obtener el lote completo de objetivos, se realiza el producto cartesiano entre las direcciones IP objetivo (hosts) contra los puertos objetivo, por ejemplo:

![Producto Cartesiano](/docs/imgs/fig_01_cartesian_product.png "Producto Cartesiano")

Una vez obtenido el producto cartesiano, se procede a *barajar* el resultado mediante un proceso de aleatorización. Este resultante aleatorio es luego dividido entre la cantidad total de nodos *trabajadores* especificados, de la siguiente manera:

![Carga de Trabajo](/docs/imgs/fig_02_workload.png "Carga de Trabajo")

Una vez obtenidos los lotes, un proceso los optimiza para que puedan ser *digeridos* más facilmente por [Nmap](https://nmap.org/). Con toda la carga de trabajo distribuída y lista para ser procesada, se procede a ejecutar el análisis entre los nodos trabajadores.

#### 2° Etapa: Bucle de gestión de nodos

Durante esta etapa, la herramienta prepara una cola de ejecución para todos los lotes de objetivos, y en base a los servicios cloud disponibles en el *pool de configuraciones*, ira creando nodos *trabajadores*, asginando un lote a cada uno y poniéndolos a funcionar.

![Multi-Cloud](/docs/imgs/fig_03_multicloud.png "Multi-Cloud")

Cada servicio cloud es altamente configurable, pudiendo establecer la cantidad de máxima de *slots* disponibles para alojar nodos, las regiones a nivel mundial donde los nodos serán creados, el tipo de imagen a instanciar (distribución de Linux o *snapshot*), etcétera. Además, estas configuraciónes se agrupan en *pools* permitiendo gestionar perfiles que se ajusten a los distintos tipos de análisis.

La carga sobre cada servicio cloud se distribuye de forma aleatoria, y en caso de no estar disponible por falla o saturación, la herramienta comienza un proceso de *round robin* para poder ubicar un nodo de trabajo en alguno de los otros servicios cloud disponibles. En caso de que no exista disponibilidad, el nodo queda en espera en la cola de trabajo hasta que se libere un *slot*.

Cada nodo creado recibe un *payload* que lo configura y prepara para recibir el lote de trabajo. Una vez listo, el nodo lanza una instancia de [Nmap](https://nmap.org/) y es monitoreado hasta que termine su trabajo. Al finalizar, el nodo entrega los resultados obtenidos y es eliminado, liberando un *slot* para ese proveedor cloud.

Mientras este proceso se lleva a cabo, se generan reportes parciales en un archivo .json que puede ser monitoreado para un seguimiento más amigable del proceso; un visor en HTML + JS acompaña la herramienta para facilitar la tarea del analista.

#### 3° Etapa: Recopilación de resultados

Una vez que todos los nodos han finalizado con su carga de trabajo y ya no quedan lotes pendientes, la herramienta reúne todos los resultados parciales para generar un resultado único en diferentes formatos según lo permite la herramienta [Nmap](https://nmap.org/) (.nmap, .gnmap y .xml).

Teniendo en cuenta la capacidad de microtarifa que poseen los proveedores de servicios cloud y virtualización, al finalizar el proceso se habrá llevado a cabo una tarea de reconocimiento desde diferentes direcciones IP, con objetivos *random* y con un costo mínimo (en línea general, suele ser menos de 1 centavo de dólar por hora de trabajo de cada nodo).

## Servicios Cloud soportados

Los drivers disponibles actualmente para servicios cloud son:

+ [Digital Ocean](https://www.digitalocean.com/) 
+ [Linode](https://www.linode.com/) 
+ [Vultr](https://www.vultr.com/) 

## Pero... ¿por qué?

La frase que resume este proyecto surgió durante una mañana a puro café:

> *Hoy es un buen día para hacer ciencia... ¿no?*
>
> *Si, así es.*

Nos gusta la ciencia. Nos gusta experimentar. Nos fascina teorizar y ver luego hasta donde llegamos. Tenemos debilidad por lanzar un proceso y luego escudriñar los resultados. Y más allá del desarrollo del proyecto y sus vicisitudes, nos encanta investigar; es por eso que, como buenos *nerds* que somos, queremos contagiar a nuestros colegas del mismo entusiasmo, compartiendo con la comunidad una herramienta que en escencia es un *proof of concept*, a sabiendas de que el esfuerzo tendrá un retorno más que grato.

Comilla, espacio, guión, guión. :wink:



















