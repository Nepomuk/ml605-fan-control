----------------------------------------------------------------------------------
-- Company:		IKP-1, FZ Jlich
-- Engineer:	Andre Goerres
--
-- Create Date:    16:30:05 27-Feb-2012
-- Design Name:
-- Module Name:    LCD Control
-- Project Name:
-- Target Devices:
-- Tool versions:
-- Description: A module to print out stuff on the LCD. Modify to get your
-- 				 information on it. Currently it has only one mode:
--                 0) [default]
--							....,....,....,.
--					 		Firmware loaded!
--							online: ##:##:##
--							
--              This is based on a module I found somewhere. Unfortunately
--              I can't remember where I found it.
--
-- Dependencies:
--
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
--
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL; 
use IEEE.NUMERIC_STD.ALL;

entity lcd_control is 
   port ( 
       RST			: in std_logic;								-- Reset
       CLK			: in std_logic;								-- Clock, 50 MHz (faster may disturb the LCD)
		 MODE			: in std_logic_vector (2 downto 0);		-- in which mode should the LCD operate? (see comments above)
       CONTROL		: out std_logic_vector (2 downto 0); 	-- (2): LCD_RS, (1): LCD_RW, (0): LCD_E
       SF_D			: out std_logic_vector (7 downto 4);		-- LCD data bus
		
		TEMP_IN			: in std_logic_vector(7 downto 0);
		TEMP_ADC_IN		: in std_logic_vector(9 downto 0);
		FAN_SPEED_IN	: in std_logic_vector(5 downto 0)
	); 
end lcd_control; 



architecture lcd_control_arch of lcd_control is

	-- the state machine for displaying information on the LCD
	type state_type is ( waiting, init_reset1, init_reset2, -- power on
								init_set_interface, init_display_off, init_display_clear, init_set_entry_mode, init_display_on, -- initialization
								lcd_idle,
								upper_line_pos, upper_line_char, lower_line_pos, lower_line_char,
								donestate);
	signal state					: state_type := waiting;
	signal next_state				: state_type := waiting;
	signal state_flag				: std_logic := '0';
	signal exit_idle_flag		: std_logic := '1';
	
	-- We need two data vectors since the ML605-LCD has only
	-- four bits for the Data Bus.
	constant dual					: std_logic := '1';	-- set to 1 if want to do clock out dual nibbles on the lcd DB
	signal sf_d_temp				: std_logic_vector (7 downto 0) := "00000000";
	signal sf_d_short				: std_logic_vector (7 downto 4) := "0000";
	
	-- count minutes and seconds
	constant cycles_per_us     : integer := 50;
	signal count, count_temp	: integer := 0;
	signal second_counter		: integer range 0 to (cycles_per_us * 1000000) + 1 := 0;	-- 1s
	signal seconds_ones			: integer range 0 to 9 := 0;
	signal seconds_tens			: integer range 0 to 5 := 0;
	signal minutes_ones			: integer range 0 to 9 := 0;
	signal minutes_tens			: integer range 0 to 5 := 0;
	signal hours_ones				: integer range 0 to 9 := 0;
	signal hours_tens				: integer range 0 to 9 := 0;
	
	-- the basis for the control-signal
	signal control_base			: std_logic_vector (2 downto 0) := "000"; -- LCD_RS, LCD_RW, LCD_E

	-- different periods for waiting
	--   note: Sometimes it happenes, that the display is
	--         not initialized correctly and is displaying
	--         nothing. Don't know why...
	--         Waiting times matched to the 200 MHz clock
	--         and modified a bit accodring to what I
	--         understood from the manual.
	constant wait_dual_1                : integer := 10 * cycles_per_us;    -- was 10us (500 cycles);
	constant wait_dual_2                : integer := 20 * cycles_per_us;    -- was 20us (1000 cycles);
	constant wait_dual_3                : integer := 40 * cycles_per_us;    -- was 40us (2000 cycles);
	constant wait_dual_4                : integer := 60 * cycles_per_us;    -- was 60us (3000 cycles);
	constant wait_power_on              : integer := 16000 * cycles_per_us; -- was 15ms (750000 cycles);
	constant wait_data_exec             : integer := 200 * cycles_per_us;   -- was 200us (10000 cycles);
	constant wait_after_data_exec       : integer := 1000 * cycles_per_us;  -- was 4,2ms (210000 cycles);
	constant wait_after_data_exec_init  : integer := 6000 * cycles_per_us;  -- was 8,4ms (420000 cycles);
	
	
	
------------------------ Character Definitions -----------------------------------
--
-- For the full list see S162D documentation.
--
-- Characters from 0x20 to 0x7d are according to the default ASCII codes with
-- one exception at 0x5c (the backslash is some japanese sign). To set a field,
-- use control_base = "100" and control = "101".
-- The positions are given by 0x80-0x8f for the first line and 0xc0-0xcf for
-- second line. Use control = "001" and control_base = "000" to set the position.
--	

	subtype lcd_char is std_logic_vector (7 downto 0);
	subtype lcd_pos  is std_logic_vector (7 downto 0);
	type lcd_line is array (15 downto 0) of lcd_char;
	
	signal upper_line       : lcd_line := (x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20");  -- 16x [blank];
	signal lower_line       : lcd_line := (x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20");  -- 16x [blank];
	signal line_pos         : integer range 0 to 15 := 0;
	signal line_pos_next    : integer range 0 to 15 := 0;
	signal line_pos_flag    : std_logic := '0';
	
	
	
	-- A function to convert a 10 bit word representing an integer
	-- to a binary coded digit (BCD) used to display each digit of
	-- of the number in one seperate LCD field.
	--
	-- Source: http://vhdlguru.blogspot.de/2010/04/8-bit-binary-to-bcd-converter-double.html
	
	function to_bcd ( bin : std_logic_vector(9 downto 0) ) return std_logic_vector is
		variable i : integer:=0;
		variable bcd : std_logic_vector(11 downto 0) := (others => '0');
		variable bint : std_logic_vector(9 downto 0) := bin;
	begin
	
		for i in 0 to 9 loop  -- repeating 10 times.
			bcd(11 downto 1) := bcd(10 downto 0);  --shifting the bits.
			bcd(0) := bint(9);
			bint(9 downto 1) := bint(8 downto 0);
			bint(0) :='0';


			if(i < 9 and bcd(3 downto 0) > "0100") then --add 3 if BCD digit is greater than 4.
				bcd(3 downto 0) := bcd(3 downto 0) + "0011";
			end if;

			if(i < 9 and bcd(7 downto 4) > "0100") then --add 3 if BCD digit is greater than 4.
				bcd(7 downto 4) := bcd(7 downto 4) + "0011";
			end if;

			if(i < 9 and bcd(11 downto 8) > "0100") then  --add 3 if BCD digit is greater than 4.
				bcd(11 downto 8) := bcd(11 downto 8) + "0011";
			end if;
			
		end loop;
		
		return bcd;
	end to_bcd;
	
	
	-- A function that converts a 4 bit hexadecimal number to
	-- the matching ASCII character values. Basically just a
	-- look up table.
	function hex2char ( hex : std_logic_vector(3 downto 0) ) return std_logic_vector is
		variable char : std_logic_vector(7 downto 0) := x"20";
	begin
		case hex is
			when x"0" => char := x"30";
			when x"1" => char := x"31";
			when x"2" => char := x"32";
			when x"3" => char := x"33";
			when x"4" => char := x"34";
			when x"5" => char := x"35";
			when x"6" => char := x"36";
			when x"7" => char := x"37";
			when x"8" => char := x"38";
			when x"9" => char := x"39";
			when x"a" => char := x"61";
			when x"b" => char := x"62";
			when x"c" => char := x"63";
			when x"d" => char := x"64";
			when x"e" => char := x"65";
			when x"f" => char := x"66";
			when others => char := x"3f";
		end case;
		return char;
	end hex2char;
	
begin 


	run : process (CLK, count, state, sf_d_temp, sf_d_short, control_base, mode,
						--chars_buffer,pos_buffer,--state_char_pos,
						line_pos, upper_line, lower_line, exit_idle_flag,
						seconds_ones,seconds_tens, minutes_ones,minutes_tens, hours_ones,hours_tens) is
		
	begin
		control_base <= "100";	-- default control is RS=1
		line_pos_flag <= '0';
		line_pos_next <= 0;

		
		case state is
		
------------------------ Initialization Starts -----------------------------------
			
			when waiting =>
				sf_d_temp <= "00000000";
				control <= "000"; 			-- clear
				if 	(count >= wait_power_on) then
						next_state <= init_reset1; state_flag <= '1';  
				else	next_state <= waiting; state_flag <= '0';
				end if;
				
			when init_reset1 => 
				sf_d_temp <= "00110000";	--reset
				if 	(count = wait_after_data_exec_init) then
						next_state <= init_reset2;	control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec_init) then
						next_state <= init_reset1; control <= "000"; state_flag <= '0';  
				else	next_state <= init_reset1; control <= "001"; state_flag <= '0';
				end if;
				
			when init_reset2 => 
				sf_d_temp <= "00110000";	--reset	
				if 	(count = wait_after_data_exec) then
						next_state <= init_set_interface;	control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init_reset2; control <= "000"; state_flag <= '0';  
				else  next_state <= init_reset2; control <= "001"; state_flag <= '0';
				end if;
				
				
			when init_set_interface =>
				sf_d_temp <= "00101100";	-- set 4bit interface, 2 lines and 5*10 dots
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= init_display_off; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init_set_interface; control <= "000"; state_flag <= '0';  
				else	next_state <= init_set_interface; control <= "001"; state_flag <= '0';
				end if;
				
			when init_display_off =>
				sf_d_temp <= "00001000"; 	-- display off
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= init_display_clear; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init_display_off; control <= "000"; state_flag <= '0';  
				else	next_state <= init_display_off; control <= "001"; state_flag <= '0';
				end if;
				
			when init_display_clear =>
				sf_d_temp <= "00000001";	 -- clear display
				control_base <= "000";		
				if 	(count = wait_after_data_exec) then
						next_state <= init_set_entry_mode; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init_display_clear; control <= "000"; state_flag <= '0';  
				else	next_state <= init_display_clear; control <= "001"; state_flag <= '0';
				end if;
				
			when init_set_entry_mode =>
				sf_d_temp <= "00000110";	 -- set entry mode: cursor increase, display not shifted
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= init_display_on; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init_set_entry_mode; control <= "000"; state_flag <= '0';  
				else	next_state <= init_set_entry_mode; control <= "001"; state_flag <= '0';
				end if;
				
			when init_display_on =>
				sf_d_temp <= "00001100";	 --Display: disp on, cursor off, blink off
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= lcd_idle; control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= init_display_on; control <= "000"; state_flag <= '0';  
				else	next_state <= init_display_on; control <= "001"; state_flag <= '0';
				end if;
				
------------------------- Initialization Ends ------------------------------------


----------------------- idle state for the LCD -----------------------------------
			when lcd_idle =>
				sf_d_temp <= "00000000";
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						if (exit_idle_flag = '1') then
							next_state <= upper_line_pos;
						else
							next_state <= lcd_idle;
						end if;
						control <= "001"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= lcd_idle; control <= "000"; state_flag <= '0';  
				else	next_state <= lcd_idle; control <= "001"; state_flag <= '0';
				end if;




----------------- Write out what is stored in the line arrays --------------------

			when upper_line_pos =>
				sf_d_temp <= x"80"; -- set address 
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= upper_line_char;
						state_flag <= '1';
						line_pos_next <= 0;
						line_pos_flag <= '1';
						control <= "001";
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= upper_line_pos;
						state_flag <= '0';
						line_pos_next <= 0;
						line_pos_flag <= '0';
						control <= "000";
				else	next_state <= upper_line_pos;
						state_flag <= '0';
						line_pos_next <= 0;
						line_pos_flag <= '0';
						control <= "001";
				end if;

			when upper_line_char =>
				sf_d_temp <= upper_line(line_pos);
				if 	(count = wait_after_data_exec) then
						if ( line_pos = 15 ) then  -- reached the end
							next_state <= lower_line_pos;
							line_pos_next <= 0;
						else
							next_state <= upper_line_char;
							line_pos_next <= line_pos + 1;
						end if;
						line_pos_flag <= '1';
						control <= "101"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= upper_line_char;
						state_flag <= '0';
						line_pos_flag <= '0';
						line_pos_next <= line_pos;
						control <= "100";
				else	next_state <= upper_line_char;
						state_flag <= '0';
						line_pos_flag <= '0';
						line_pos_next <= line_pos;
						control <= "101";
				end if;
				
				
			when lower_line_pos =>
				sf_d_temp <= x"c0"; -- set address 
				control_base <= "000";
				if 	(count = wait_after_data_exec) then
						next_state <= lower_line_char;
						state_flag <= '1';
						line_pos_next <= 0;
						line_pos_flag <= '1';
						control <= "001";
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= lower_line_pos;
						state_flag <= '0'; 
						line_pos_next <= 0;
						line_pos_flag <= '0'; 
						control <= "000";
				else	next_state <= lower_line_pos;
						state_flag <= '0';
						line_pos_next <= 0;
						line_pos_flag <= '0';
						control <= "001";
				end if;

			when lower_line_char =>
				sf_d_temp <= lower_line(line_pos);
				if 	(count = wait_after_data_exec) then
						if ( line_pos = 15 ) then  -- reached the end
							next_state <= upper_line_pos;
							line_pos_next <= 0;
						else
							next_state <= lower_line_char;
							line_pos_next <= line_pos + 1;
						end if;
						line_pos_flag <= '1';
						control <= "101"; state_flag <= '1';
				elsif (count > wait_data_exec AND count <= wait_after_data_exec) then
						next_state <= lower_line_char;
						state_flag <= '0';
						line_pos_flag <= '0';
						line_pos_next <= line_pos;
						control <= "100";
				else	next_state <= lower_line_char;
						state_flag <= '0';
						line_pos_flag <= '0';
						line_pos_next <= line_pos;
						control <= "101";
				end if;


----------------------- finished state -------------------------------------------
			when donestate =>
				control <= "100";
				sf_d_temp <= "00000000";
				if 	(count = wait_after_data_exec) then
						next_state <= donestate; state_flag <= '1';
				else	next_state <= donestate; state_flag <= '0';
				end if;
				
			-- go to reset
			when others =>
				sf_d_temp <= "00000000"; control <= "000";
				next_state <= waiting; state_flag <= '1';
				
		end case;
	
	
	
		-- if dual mode, then strobe out the high nibble before setting to low nibble, but if not dual, then just put out the high nibble
		
		if (dual = '1') then
			if (count <= wait_dual_1) then
				sf_d_short <= sf_d_temp(7 downto 4);
				control<= control_base or "001";
			elsif (count > wait_dual_1 and count <= wait_dual_2) then
				sf_d_short <= sf_d_temp(7 downto 4);
				control<= control_base;
			elsif (count > wait_dual_2 and count <= wait_dual_3) then
				sf_d_short <= sf_d_temp(7 downto 4);
				control<= control_base or "001";
			elsif (count > wait_dual_3 and count <= wait_dual_4) then
				sf_d_short <= sf_d_temp(7 downto 4); 
				control<= control_base or "001";
			else
				sf_d_short <= sf_d_temp(3 downto 0);
			end if;
		else
			sf_d_short <= sf_d_temp(7 downto 4);
		end if;
		
	end process run;
	
	
	
	what_to_display : process (RST, CLK, mode, hours_tens, hours_ones, minutes_tens, minutes_ones, seconds_tens, seconds_ones ) is
		variable temp_bcd			: std_logic_vector(11 downto 0);
		variable temp_adc_bcd		: std_logic_vector(11 downto 0);
		variable fan_speed_bcd		: std_logic_vector(11 downto 0);
	begin
		if rising_edge(CLK) then
			if (RST = '1') then
				upper_line <= (x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20");  -- 16x [blank]
				lower_line <= (x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20");  -- 16x [blank]
				
				
			elsif mode = "000" then
				upper_line( 0) <= x"46"; -- F
				upper_line( 1) <= x"69"; -- i
				upper_line( 2) <= x"72"; -- r
				upper_line( 3) <= x"6d"; -- m
				upper_line( 4) <= x"77"; -- w
				upper_line( 5) <= x"61"; -- a
				upper_line( 6) <= x"72"; -- r
				upper_line( 7) <= x"65"; -- e
				upper_line( 8) <= x"20"; -- 
				upper_line( 9) <= x"6c"; -- l
				upper_line(10) <= x"6f"; -- o
				upper_line(11) <= x"61"; -- a
				upper_line(12) <= x"64"; -- d
				upper_line(13) <= x"65"; -- e
				upper_line(14) <= x"64"; -- d
				upper_line(15) <= x"21"; -- !
				
				lower_line( 0) <= x"6f"; -- o
				lower_line( 1) <= x"6e"; -- n
				lower_line( 2) <= x"6c"; -- l
				lower_line( 3) <= x"69"; -- i
				lower_line( 4) <= x"6e"; -- n
				lower_line( 5) <= x"65"; -- e
				lower_line( 6) <= x"3a"; -- :
				lower_line( 7) <= x"20"; -- 
				lower_line( 8) <= x"30" or std_logic_vector(to_unsigned(hours_tens, 4)); -- [0..9]
				lower_line( 9) <= x"30" or std_logic_vector(to_unsigned(hours_ones, 4)); -- [0..9]
				lower_line(10) <= x"3a"; -- :
				lower_line(11) <= x"30" or std_logic_vector(to_unsigned(minutes_tens, 4)); -- [0..5]
				lower_line(12) <= x"30" or std_logic_vector(to_unsigned(minutes_ones, 4)); -- [0..9]
				lower_line(13) <= x"3a"; -- :
				lower_line(14) <= x"30" or std_logic_vector(to_unsigned(seconds_tens, 4)); -- [0..5]
				lower_line(15) <= x"30" or std_logic_vector(to_unsigned(seconds_ones, 4)); -- [0..9]
				
				
			elsif mode = "001" then
				temp_bcd := to_bcd("0000000000" or TEMP_IN);
				temp_adc_bcd := to_bcd("0000000000" or TEMP_ADC_IN);
				fan_speed_bcd := to_bcd("0000000000" or FAN_SPEED_IN);
				
				upper_line( 0) <= x"54"; -- T
				upper_line( 1) <= x"3a"; -- :
				upper_line( 2) <= x"20"; -- 
				upper_line( 3) <= x"30" or temp_bcd(7 downto 4); -- [0..9]
				upper_line( 4) <= x"30" or temp_bcd(3 downto 0); -- [0..9]
				upper_line( 5) <= x"df"; -- 
				upper_line( 6) <= x"43"; -- C
				upper_line( 7) <= x"20"; -- 
				upper_line( 8) <= x"41"; -- A
				upper_line( 9) <= x"44"; -- D
				upper_line(10) <= x"43"; -- C
				upper_line(11) <= x"3a"; -- :
				upper_line(12) <= x"20"; -- 
				upper_line(13) <= x"30" or temp_adc_bcd(11 downto 8); -- [0..9]
				upper_line(14) <= x"30" or temp_adc_bcd(7 downto 4); -- [0..9]
				upper_line(15) <= x"30" or temp_adc_bcd(3 downto 0); -- [0..9]
				
				lower_line( 0) <= x"46"; -- F
				lower_line( 1) <= x"61"; -- a
				lower_line( 2) <= x"6e"; -- n
				lower_line( 3) <= x"20"; -- 
				lower_line( 4) <= x"73"; -- s
				lower_line( 5) <= x"70"; -- p
				lower_line( 6) <= x"65"; -- e
				lower_line( 7) <= x"65"; -- e
				lower_line( 8) <= x"64"; -- d
				lower_line( 9) <= x"3a"; -- :
				lower_line(10) <= x"20"; -- 
				if ( fan_speed_bcd(7 downto 0) = x"00" ) then
					lower_line(11) <= x"2d"; -- -
					lower_line(12) <= x"2d"; -- -
				else
					lower_line(11) <= x"30" or fan_speed_bcd(7 downto 4); -- [0..1]
					lower_line(12) <= x"30" or fan_speed_bcd(3 downto 0); -- [0..9]
				end if;
				lower_line(13) <= x"20"; -- 
				lower_line(14) <= x"20"; -- 
				lower_line(15) <= x"20"; -- 
			end if;
		end if;
	end process what_to_display;
	
	
	clock : process (RST, CLK) is
		variable tmp_seconds_ones : integer range 0 to 10;
		variable tmp_seconds_tens : integer range 0 to 6;
		variable tmp_minutes_ones : integer range 0 to 10;
		variable tmp_minutes_tens : integer range 0 to 6;
		variable tmp_hours_ones : integer range 0 to 10;
		variable tmp_hours_tens : integer range 0 to 10;
	begin
		if (rising_edge(CLK)) then
			if (RST = '1') then
				second_counter <= 0;
				seconds_ones <= 0;
				seconds_tens <= 0;
				minutes_ones <= 0;
				minutes_tens <= 0;
				hours_ones <= 0;
				hours_tens <= 0;
			elsif (second_counter = cycles_per_us * 1000000) then
				-- get the next number for each digit
				tmp_seconds_ones := seconds_ones + 1;
				if (tmp_seconds_ones = 10) then
					tmp_seconds_ones := 0;
					tmp_seconds_tens := seconds_tens + 1;
				end if;
				if (tmp_seconds_tens = 6) then
					tmp_seconds_tens := 0;
					tmp_minutes_ones := minutes_ones + 1;
				end if;
				if (tmp_minutes_ones = 10) then
					tmp_minutes_ones := 0;
					tmp_minutes_tens := minutes_tens + 1;
				end if;
				if (tmp_minutes_tens = 6) then
					tmp_minutes_tens := 0;
					tmp_hours_ones := hours_ones + 1;
				end if;
				if (tmp_hours_ones = 10) then
					tmp_hours_ones := 0;
					tmp_hours_tens := hours_tens + 1;
				end if;
				
				-- we have reached the end of our cycle, reset
				if (tmp_hours_tens = 10) then
					tmp_seconds_ones := 0;
					tmp_seconds_tens := 0;
					tmp_minutes_ones := 0;
					tmp_minutes_tens := 0;
					tmp_hours_ones := 0;
					tmp_hours_tens := 0;
				end if;
				
				-- set the signals
				second_counter <= 0;
				seconds_ones <= tmp_seconds_ones;
				seconds_tens <= tmp_seconds_tens;
				minutes_ones <= tmp_minutes_ones;
				minutes_tens <= tmp_minutes_tens;
				hours_ones <= tmp_hours_ones;
				hours_tens <= tmp_hours_tens;
			else
				second_counter <= second_counter + 1;
			end if;
		end if;
	end process clock;
	
	
	timing : process (RST, CLK) is
	begin
		if	(rising_edge(CLK)) then
			sf_d <= sf_d_short;
			count <= count_temp;
			if (RST = '1') then
				state <= waiting;
				count_temp <= 0;
			elsif (state_flag = '1') then
				state <= next_state;
				count_temp <= 0;
			else
				state <= next_state;
				count_temp <= count_temp + 1;
			end if;
			
			if ( RST = '1' ) then
				line_pos <= 0;
			elsif ( line_pos_flag = '1' ) then
				line_pos <= line_pos_next;
			else
				line_pos <= line_pos;
			end if;
		end if;
	end process timing;

end lcd_control_arch;  