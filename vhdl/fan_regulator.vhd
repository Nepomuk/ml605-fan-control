-- -----------------------------------------------------------------------------
--
--                         Andre Goerres  |       ######
--    Institut fuer Kernphysik 1 (IKP-1)  |    #########
--        Forschungszentrum Juelich GmbH  |   #########   ##
--              D-52425 Juelich, Germany  |  #########   ####
--                                        |  ########   #####
--             (+49)2461 61 6225 :   Tel  |   #   ##   #####
--             (+49)2461 61 3573 :   FAX  |    ##     #####
--       a.goerres@fz-juelich.de : E-Mail |       ######
--
-- -----------------------------------------------------------------------------
-- =============================================================================
--
--	project:		 PANDA
--	module:		 fan_regulator
--              A module regulating the fan depending on the FPGAs temperature.
--	author:		 A.Goerres, IKP
--
-- description: To include this fan regulating module, you have to provide a
--              clock (66 MHz at default) and the pin for the fan control.
--              You are free to choose another clock frequency between 8 and
--              80 MHz, but be sure you include the same in the sysmon IP core.
--
--              Also you have to create an IP core for the system monitor (sysmon)
--              which comes with the Xilinx IP core generator. In the core you
--              should enable averaging over 16 measurements to get less statistical
--              fluctuations.
--
--              There is a temperature display on the LCD. If you don't want to use
--              it, just leave the ports open and don't use the LCD module.
--
-- History
-- Date     | Rev | Author    | What
-- ---------+-----+-----------+-------------------------------------------------
-- 22.05.12 | 1.0 | A.Goerres | initial version of fan controller
-- ---------+-----+-----------+-------------------------------------------------
--
-- ======================================================================= --

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL; 

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;



--------------------------------------------------------------------
-- begin entity

entity fan_regulator is
	port (
	   -- system signals
		CLK				: in  STD_LOGIC;       -- 50 MHz clock
		RESET          : in  STD_LOGIC;       -- global reset
		
		-- the fan output
		FAN_PWM			: out STD_LOGIC;
		
		-- some output values for displaying on the LCD
		TEMP_OUT			: out std_logic_vector(7 downto 0);
		TEMP_ADC_OUT	: out std_logic_vector(9 downto 0);
		FAN_SPEED_OUT	: out std_logic_vector(5 downto 0)
		
	);
end fan_regulator;

-- end entity
--------------------------------------------------------------------


--------------------------------------------------------------------
-- begin architecture

architecture Behavioral of fan_regulator is

	-- start component declaration -------------------------------------
	
	component sysmon_wiz_v2_1
		port (
			RESET_IN            : in  STD_LOGIC;                         -- Reset signal for the System Monitor control logic
		
			-- data ports
			DADDR_IN            : in  STD_LOGIC_VECTOR (6 downto 0);     -- Address bus for the dynamic reconfiguration port
			DCLK_IN             : in  STD_LOGIC;                         -- Clock input for the dynamic reconfiguration port
			DEN_IN              : in  STD_LOGIC;                         -- Enable Signal for the dynamic reconfiguration port
			DI_IN               : in  STD_LOGIC_VECTOR (15 downto 0);    -- Input data bus for the dynamic reconfiguration port
			DWE_IN              : in  STD_LOGIC;                         -- Write Enable for the dynamic reconfiguration port
			DO_OUT              : out STD_LOGIC_VECTOR (15 downto 0);    -- Output data bus for dynamic reconfiguration port
			DRDY_OUT            : out STD_LOGIC;                         -- Data ready signal for the dynamic reconfiguration port
			
			-- alarm outputs
			OT_OUT              : out STD_LOGIC;                         -- Over-Temperature alarm output
			VCCAUX_ALARM_OUT    : out STD_LOGIC;                         -- VCCAUX-sensor alarm output
			VCCINT_ALARM_OUT    : out STD_LOGIC;                         -- VCCINT-sensor alarm output
			USER_TEMP_ALARM_OUT : out STD_LOGIC;                         -- Temperature-sensor alarm output
			
			-- Dedicated Analog Input Pair
			VP_IN               : in  STD_LOGIC;
			VN_IN               : in  STD_LOGIC
		);
	end component;
	
	
	
	-- start singal declaration ----------------------------------------
	
	constant clk_freq          : integer := 50000000;  -- one second at clock frequency
	constant temp_address      : std_logic_vector (7 downto 0) := x"00";
	
	-- Define ranges for temperature that defines, how rapidly the
	-- fan speed should be changed.
	--   1) target_temp - 2C    => min fan speed
	--   2) up to  + 10C        => change fan speed and wait 2s to make further changes
	--   3) greater than + 10C  => max fan speed
	constant temp_target_value    : integer := 636;  -- try to hold the temperature at this value  (cur: ~40C)
	                                                 --  (616 => 30C, 636 => 40C, 657 => 50C)
																	 --  (max. for Virtex 6: 85C)
	constant temp_max_difference  : integer := 20;   -- 20 ADC-steps => 10C
	
	-- it is more easy to just give the fan speed in ADC values
	constant fan_speed_min     : integer := 8;   -- ~1/4 is the minimum duty cycle for the fan to run
	constant fan_speed_max     : integer := temp_max_difference + fan_speed_min;
	signal fan_speed           : integer range 0 to fan_speed_max;
	signal pwm_int             : std_logic;
	
	-- some counting values
	signal ctr_on              : integer range 0 to fan_speed_max := 0;
	signal ctr_fan             : integer range 0 to fan_speed_max := 0;
	
	-- If the temperature is averaged over 256 measurements (can be 
	-- configured in the sysmon IP core) and the clock is 50 MHz this
	-- leads to new temperature values roughly every 100 milliseconds.
	constant temp_read_cycle : integer := 2000000;
	signal ctr_temp          : integer range 0 to (temp_read_cycle+1);
	
	signal tmp_data_read   : std_logic;
	signal temp_data_out   : std_logic_vector (15 downto 0);
	signal temp_data_ready : std_logic;
	signal temp_current    : integer range 0 to 1023;



begin

	FAN_PWM <= pwm_int;
	
	U_SYSMON : sysmon_wiz_v2_1
	port map ( 
		RESET_IN            => RESET,
		
		-- data ports
		DADDR_IN            => temp_address(6 downto 0), 
		DCLK_IN             => CLK, 
		DEN_IN              => tmp_data_read, 
		DI_IN               => (others => '0'),
		DWE_IN              => '0',
		DO_OUT              => temp_data_out,
		DRDY_OUT            => temp_data_ready,
		
		-- alarm outputs
		OT_OUT              => open,
		VCCAUX_ALARM_OUT    => open,
		VCCINT_ALARM_OUT    => open,
		USER_TEMP_ALARM_OUT => open,
		
		-- Dedicated Analog Input Pair
		VP_IN               => '0', 
		VN_IN               => '0'
	);
		
		
	-- translate the temperature into an integer
	process ( CLK, temp_data_out, temp_data_ready )
		variable tmp_temp_current  : integer range 0 to 1023;
		variable tmp_temp_celcius  : std_logic_vector(8 downto 0);
	begin
		if rising_edge(CLK) then
			if temp_data_ready = '1' then
				tmp_temp_current := to_integer(unsigned( temp_data_out(15 downto 6) ));
				
				-- There is sometimes a bug in the temperature value: when at
				-- around 42C, the ADC shows suddenly a value much higher/lower
				-- than before. That can't be right, so lets set it then fixed
				-- to 42C (equals ADC 640).
				if ( tmp_temp_current = 544 or tmp_temp_current = 767 ) then
					tmp_temp_current := 640;
				end if;
				
				temp_current <= tmp_temp_current;
				
				
				tmp_temp_celcius := temp_data_out(15 downto 7) - 278;
				TEMP_OUT <= tmp_temp_celcius(7 downto 0);
				
				TEMP_ADC_OUT <= temp_data_out(15 downto 6);
			end if;
		end if;
	end process;
	
	
	-- check, if the temperature changes and adapt the fan setting
	process ( CLK, temp_current )
		variable tmp_fan_speed         : integer range 0 to fan_speed_max*2;
	begin
		if rising_edge( CLK ) then
		
			-- we have reached the maximum difference accepted - turn to max speed
			if ( temp_current > temp_target_value + temp_max_difference ) then
				fan_speed <= fan_speed_max;
				
			-- we are below target temperature - turn to min speed
			elsif ( temp_current <= temp_target_value ) then
				fan_speed <= fan_speed_min;
			
			else
			
				-- the fan speed is given in ADC steps difference from target temperature
				tmp_fan_speed := temp_current - temp_target_value + fan_speed_min;
				
				-- apply the new fan speed
				if ( tmp_fan_speed >= fan_speed_max ) then
					fan_speed <= fan_speed_max;
				elsif ( tmp_fan_speed < fan_speed_min ) then
					fan_speed <= fan_speed_min;
				else
					fan_speed <= tmp_fan_speed;
				end if;
				
			end if; -- end temperature switch
			
			if ( fan_speed > 0 ) then
				FAN_SPEED_OUT <= std_logic_vector(to_unsigned(fan_speed-fan_speed_min+1, FAN_SPEED_OUT'length));
			else
				FAN_SPEED_OUT <= (others => '0');
			end if;
			
		end if;
	end process;
	

	-- enable the fan for a fraction of 20 clock cycles
	process ( CLK )
	begin
		if rising_edge( CLK ) then
			if ( ctr_temp = temp_read_cycle ) then
				tmp_data_read <= '1';
				ctr_temp <= 0;
			else
				tmp_data_read <= '0';
				ctr_temp <= ctr_temp + 1;
			end if;
		
		
			if ( ctr_fan = fan_speed_max ) then
				ctr_fan <= 0;
				ctr_on <= 0;
				pwm_int <= '1';
			else
				if ( ctr_on >= fan_speed ) then
					pwm_int <= '0';
					ctr_on <= ctr_on;
				else
					pwm_int <= '1';
					ctr_on <= ctr_on + 1;
				end if;
				ctr_fan <= ctr_fan + 1;
				tmp_data_read <= '0';
			end if;
		end if;
	end process;

end Behavioral;

