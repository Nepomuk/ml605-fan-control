ML605 fan controller
====================

This module controls the speed of the fan, mounted on the FPGA (Virtex 6) of the ML605 development board from 
Xilinx. It regulates the speed depending on the temperature.

Installation
------------

Just import the .xise file as a project in the Xilinx ISE. At least with version 13.4 under Linux it is 
compiling.

Usage
-----

The fan controller tries to hold a temperature of 40°C and increases the fan speed continuously if the 
temperature rises. You can change the values if you want, they are all in the signal declaration part.

###ADC to temperature
The temperature is measured at the FPGA and digitized by a system monitor that is accessible via a Xilinx IP 
core. The ADC values from this system monitor transfer into a temperature with this equation:

>`Temperature (°C) = [ADC code] * 503.975 / 1024 - 273.15`

Some common temperatures would be:

    616 ADC = 30 °C
    626 ADC = 35 °C
    636 ADC = 40 °C
    657 ADC = 50 °C

###LCD information
This project uses my [LCD module](https://github.com/Nepomuk/ml605-lcd) to display current temperature and 
corresponding ADC values as well as the current fan speed setting.

###Fan speed
The fan speed is controlled by a duty cycle. If you take for instance 10 clock cycles and only power the fan for 
5 of these 10 cycles, you get the speed running at half speed. 

Known Bugs
----------

* Sometimes the system monitor delivers strange ADC values. I seems to appear only at around 42°C where the ADC 
values jump to 544 (= -5°C) or 767 (= 103°C). My dirty solution is to catch these values and set them manually 
to 640 (= 42°C).
