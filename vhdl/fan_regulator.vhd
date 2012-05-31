-- -----------------------------------------------------------------------------
--
--                         Andr Goerres  |       ######
--     Institut fr Kernphysik 1 (IKP-1)  |    #########
--        Forschungszentrum Juelich GmbH  |   #########   ##
--              D-52425 Juelich, Germany  |  #########   ####
--                                        |  ########   #####
--             (+49)2461 61 6225 :   Tel  |   #   ##   #####
--             (+49)2461 61 3573 :   FAX  |    ##     #####
--       a.goerres@fz-juelich.de : EMail  |       ######
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
--              There is a temperature display on the 8 user LEDs next to the
--              user switches which you can use. If not, leave the port open.
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

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;



--------------------------------------------------------------------
-- begin entity

entity fan_regulator is
	port (
	   -- system signals
		CLK_66			: in  STD_LOGIC;       -- 66 MHz clock
		RESET          : in  STD_LOGIC;       -- global reset
		DISPLAY			: out STD_LOGIC_VECTOR (7 downto 0); 
		
		-- the fan output
		FAN_PWM			: out STD_LOGIC
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
	
	constant clk_freq          : integer := 66000000;  -- one second at clock frequency
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
	constant fan_speed_min     : integer := 7;   -- ~1/4 is the minimum duty cycle for the fan to run
	constant fan_speed_max     : integer := temp_max_difference + fan_speed_min;
	signal fan_speed           : integer range 0 to fan_speed_max;
	signal pwm_int             : std_logic;
	
	-- some counting values
	signal ctr_on              : integer range 0 to fan_speed_max := 0;
	signal ctr_fan             : integer range 0 to fan_speed_max := 0;
	
	-- If the temperature is averaged over 16 measurements (can be 
	-- configured in the sysmon IP core) and the clock is 66 MHz this
	-- leads to new temperature values every three seconds.
	constant temp_read_cycle : integer := 4125000 * 3;
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
		DCLK_IN             => CLK_66, 
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
	
	process ( temp_current )
	begin
		if ( temp_current < 606 ) then   -- < 25C
			DISPLAY <= "00000000";
		elsif ( temp_current >= 606 and temp_current < 626  ) then      -- 25,0-35,0C
			DISPLAY (3 downto 0) <= "0001";
			if ( temp_current >= 606 and temp_current < 611  ) then      --   25,0-27,5C
				DISPLAY (7 downto 4) <= "0001";
			elsif ( temp_current >= 611 and temp_current < 616  ) then   --   27,5-30,0C
				DISPLAY (7 downto 4) <= "0011";
			elsif ( temp_current >= 616 and temp_current < 621  ) then   --   30,0-32,5C
				DISPLAY (7 downto 4) <= "0111";
			elsif ( temp_current >= 621 and temp_current < 626  ) then   --   32,5-35,0C
				DISPLAY (7 downto 4) <= "1111";
			else
				DISPLAY (7 downto 4) <= "0000";
			end if;
		elsif ( temp_current >= 626 and temp_current < 646  ) then      -- 35,0-45,0C
			DISPLAY (3 downto 0) <= "0011";
			if ( temp_current >= 626 and temp_current < 631  ) then      --   35,0-37,5C
				DISPLAY (7 downto 4) <= "0001";
			elsif ( temp_current >= 631 and temp_current < 636  ) then   --   37,5-40,0C
				DISPLAY (7 downto 4) <= "0011";
			elsif ( temp_current >= 636 and temp_current < 641  ) then   --   40,0-42,5C
				DISPLAY (7 downto 4) <= "0111";
			elsif ( temp_current >= 641 and temp_current < 646  ) then   --   42,5-45,0C
				DISPLAY (7 downto 4) <= "1111";
			else
				DISPLAY (7 downto 4) <= "0000";
			end if;
		elsif ( temp_current >= 646 and temp_current < 667  ) then      -- 45,0-55,0C
			DISPLAY (3 downto 0) <= "0111";
			if ( temp_current >= 646 and temp_current < 652  ) then      --   45,0-47,5C
				DISPLAY (7 downto 4) <= "0001";
			elsif ( temp_current >= 652 and temp_current < 657  ) then   --   47,5-40,0C
				DISPLAY (7 downto 4) <= "0011";
			elsif ( temp_current >= 657 and temp_current < 662  ) then   --   50,0-52,5C
				DISPLAY (7 downto 4) <= "0111";
			elsif ( temp_current >= 662 and temp_current < 667  ) then   --   52,5-55,0C
				DISPLAY (7 downto 4) <= "1111";
			else
				DISPLAY (7 downto 4) <= "0000";
			end if;
		elsif ( temp_current >= 667 ) then   -- > 55C
			DISPLAY <= "11111111";
		else
			DISPLAY <= "10101010";
		end if;

--		if ( temp_current < 606 ) then   -- < 25C
--			DISPLAY <= "00000000";
--		elsif ( temp_current >= 606 and temp_current < 616  ) then      -- 25,0-30,0C
--			DISPLAY (3 downto 0) <= "0001";
--			if ( temp_current >= 606 and temp_current < 608  ) then      --   25,0-26,0C
--				DISPLAY (7 downto 4) <= "0000";
--			elsif ( temp_current >= 608 and temp_current < 610  ) then   --   26,0-27,0C
--				DISPLAY (7 downto 4) <= "0001";
--			elsif ( temp_current >= 610 and temp_current < 612  ) then   --   27,0-28,0C
--				DISPLAY (7 downto 4) <= "0011";
--			elsif ( temp_current >= 612 and temp_current < 614  ) then   --   28,0-29,0C
--				DISPLAY (7 downto 4) <= "0111";
--			elsif ( temp_current >= 614 and temp_current < 616  ) then   --   29,0-30,0C
--				DISPLAY (7 downto 4) <= "1111";
--			end if;
--		elsif ( temp_current >= 616 and temp_current < 626  ) then      -- 30,0-35,0C
--			DISPLAY (3 downto 0) <= "0011";
--			if ( temp_current >= 616 and temp_current < 618  ) then      --   30,0-31,0C
--				DISPLAY (7 downto 4) <= "0000";
--			elsif ( temp_current >= 618 and temp_current < 620  ) then   --   31,0-32,0C
--				DISPLAY (7 downto 4) <= "0001";
--			elsif ( temp_current >= 620 and temp_current < 622  ) then   --   32,0-33,0C
--				DISPLAY (7 downto 4) <= "0011";
--			elsif ( temp_current >= 622 and temp_current < 624  ) then   --   33,0-34,0C
--				DISPLAY (7 downto 4) <= "0111";
--			elsif ( temp_current >= 624 and temp_current < 626  ) then   --   34,0-35,0C
--				DISPLAY (7 downto 4) <= "1111";
--			end if;
--		elsif ( temp_current >= 626 and temp_current < 636  ) then      -- 35,0-40,0C
--			DISPLAY (3 downto 0) <= "0111";
--			if ( temp_current >= 626 and temp_current < 628  ) then      --   35,0-36,0C
--				DISPLAY (7 downto 4) <= "0000";
--			elsif ( temp_current >= 628 and temp_current < 630  ) then   --   36,0-37,0C
--				DISPLAY (7 downto 4) <= "0001";
--			elsif ( temp_current >= 630 and temp_current < 632  ) then   --   37,0-38,0C
--				DISPLAY (7 downto 4) <= "0011";
--			elsif ( temp_current >= 632 and temp_current < 634  ) then   --   38,0-39,0C
--				DISPLAY (7 downto 4) <= "0111";
--			elsif ( temp_current >= 634 and temp_current < 636  ) then   --   39,0-40,0C
--				DISPLAY (7 downto 4) <= "1111";
--			end if;
--		elsif ( temp_current >= 636 and temp_current < 646  ) then      -- 40,0-45,0C
--			DISPLAY (3 downto 0) <= "1111";
--			if ( temp_current >= 636 and temp_current < 638  ) then      --   40,0-41,0C
--				DISPLAY (7 downto 4) <= "0000";
--			elsif ( temp_current >= 638 and temp_current < 640  ) then   --   41,0-42,0C
--				DISPLAY (7 downto 4) <= "0001";
--			elsif ( temp_current >= 640 and temp_current < 642  ) then   --   42,0-43,0C
--				DISPLAY (7 downto 4) <= "0011";
--			elsif ( temp_current >= 642 and temp_current < 644  ) then   --   43,0-44,0C
--				DISPLAY (7 downto 4) <= "0111";
--			elsif ( temp_current >= 644 and temp_current < 646  ) then   --   44,0-45,0C
--				DISPLAY (7 downto 4) <= "1111";
--			end if;
--		elsif ( temp_current >= 646 ) then   -- > 45C
--			DISPLAY <= "10101010";
--		else
--			DISPLAY <= "10000001";
--		end if;
	end process;
		
		
	-- translate the temperature into an integer
	process ( temp_data_out, temp_data_ready )
	begin
		if rising_edge( temp_data_ready ) then
			temp_current <= to_integer(unsigned( temp_data_out(15 downto 6) ));
		end if;
	end process;
	
	
	-- check, if the temperature changes and adapt the fan setting
	process ( temp_current )
		variable tmp_fan_speed         : integer range 0 to fan_speed_max*2;
	begin
	
		-- we have reached the maximum difference accepted - turn to max speed
		if ( temp_current > temp_target_value + temp_max_difference ) then
			fan_speed <= fan_speed_max;
			
		-- we are below target temperature - turn to min speed
		elsif ( temp_current <= temp_target_value ) then
			fan_speed <= 0;
		
		-- apparently we are not in the extreme region, so lets moderate the fan speed
		--elsif ( temp_current > temp_target_value ) then
		else
		
			-- the fan speed is given in ADC steps difference from target temperature
			tmp_fan_speed := temp_current - temp_target_value + fan_speed_min;
			
			-- apply the new fan speed
			if ( tmp_fan_speed >= fan_speed_max ) then
				fan_speed <= fan_speed_max;
			elsif ( tmp_fan_speed < fan_speed_min ) then
				fan_speed <= 0;
			else
				fan_speed <= tmp_fan_speed;
			end if;
			
		end if; -- end temperature switch
		
	end process;
	

	-- enable the fan for a fraction of 20 clock cycles
	process ( CLK_66 )
	begin
		if rising_edge( CLK_66 ) then
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

