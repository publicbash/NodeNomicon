# NodeNomicon
Distributed over multi-cloud NMAP scanner.

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
 Dex0r & Kaleb @ OpenBASH
 2022-08-04
--------------------------------------------------------------------------------

 Logo Art:
    Book: Donovan Bake
    Text: TextKool (textkool.com)
    Edit: Kaleb
--------------------------------------------------------------------------------

Usage:
  ./nodenomicon.sh -t 10.0.0.0/24 -p 1-100 -w 5 --optimize-data-gen
  ./nodenomicon.sh -t 10.0.0.0/24 -p top-10 -w 5 --optimize-data-gen
  ./nodenomicon.sh -c /etc/nodenomicon -t 'scanme.nmap.org' -p 80,443 -w 2 -d ./scan_output
  ./nodenomicon.sh -t 'scanme.nmap.org' -p 5900-5999 -w 4 --nmap-params '-n -sS -T5 -O -sC'
  ./nodenomicon.sh --config-pool /etc/nodenomicon/bigpool --targets-file scan_targets.txt -p 80,443 -w 2 -d ./scan_output --torify
  ./nodenomicon.sh --targets '10.0.0.0/28 10.0.0.100-200' --ports 1-100 --worker-count 5 --work-dir ./scan_output
  ./nodenomicon.sh -t '192.168.0.0/28' --ports top-100 --w 4 --xml-output /mnt/ssd_1/test_01.xml --nmap-output /mnt/ssd_2/nmap_output.nmap
  ./nodenomicon.sh -t 'scanme.nmap.org' --ports top-1000 --w 12 --gnmap-output /mnt/ssd_1/test_02.gnmap --queue-output /mnt/ssd_2/queue.json

Help:
  -t, --targets EXPR    Specifies targets using same sintax as nmap. Use single quotes for multiple targets.
  --targets-file FILE   Specifies targets using an input file. Must have one target per line.
  -p, --ports EXPR      Specifies port range using same sintax as nmap. If the 'top-NNNN' sintax is used,
                        then the top-ports NNNN will be used to generate the scan targets (NNNN is a number
                        between 1 and 65535).
  -w, --workers NUMBER  Specifies to how many workers will the scan be distributed.
  -c, --config-pool DIR Specifies a directory to pool the virtualization provider configurations. Will pick
                        a random .cfg file, and if no slots are available using that configuration, it will 
                        'round-robin' through them. Defaults to '/etc/nodenomicon'.
  -d, --work-dir DIR    Specifies the output working directory. Directory MUST BE EMPTY. If not specified,
                        a ./work/scan_NNN directory will be created.
  -r, --parallel EXPR   Specifies how many workers (maximum) will be running in parallel (created and
                        monitored) to reduce api calls to VPS providers. Can be 'full', 'auto' or a positive
                        number. If 'full', a working node will be spawned for each work data; if 'auto',
                        sumatory of parameter 'max-node-count' from all of the configuration pool files will
                        be will be used. Defaults to 'auto'.
  --nmap-params STRING  Specifies custom nmap parameters, enclosed with quotes. If ommited, the scan will be
                        done with '-sV -T4 -Pn --resolve-all'. Avoid using these parameters: -iL, -p, -oA.
  --xml-output FILE     Makes a copy of output.xml (partial and final) to desired destination.
  --nmap-output FILE    Makes a copy of output.nmap (partial and final) to desired destination.
  --gnmap-output FILE   Makes a copy of output.gnmap (partial and final) to desired destination.
  --queue-output FILE   Makes a copy of monitor queue to desired destination.
  --torify              Specifies if tor network must be used to reach the nodes provider API.
  --optimize-data-gen   When creating target & port working parameters, specifies to autodetect cpu core count
                        for parallel tasks.
  --dry-run             Only generates workers data, but do not run the distrubuted scan.
  -h, --help            This help.

```