----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date:    15:10:09 05/21/2012 
-- Design Name: 
-- Module Name:    topl - Behavioral 
-- Project Name: 
-- Target Devices: 
-- Tool versions: 
-- Description: 
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity topl is
	port(
	
		-- System signals
		------------------
      RESET	              : in  std_logic;	 		-- asynchronous reset
      CLK_IN_P            : in  std_logic;    		-- 200MHz clock input from board
      CLK_IN_N            : in  std_logic;      
		SM_FAN_PWM			  : out std_logic;
		
		-- LCD  interface
		------------------
		SF_D                : out std_logic_vector(3 downto 0);	-- LCD data bus
		LCD_E               : out std_logic;							-- LCD: E   (control bit)
		LCD_RS              : out std_logic;							-- LCD: RS  (setup or data)
		LCD_RW              : out std_logic								-- LCD: R/W (read or write)
		
		
	);
end topl;

architecture Behavioral of topl is

	------------------------------------------------------------------------------
	-- Component Declaration
	------------------------------------------------------------------------------
  
	component fan_regulator
		port (
			CLK         : in  STD_LOGIC;
			RESET       : in  STD_LOGIC;
			FAN_PWM		: out STD_LOGIC;
		
			TEMP_OUT			: out std_logic_vector(7 downto 0);
			TEMP_ADC_OUT	: out std_logic_vector(9 downto 0);
			FAN_SPEED_OUT	: out std_logic_vector(5 downto 0)
		);
	end component;
	
	component lcd_control
		port (
			RST				: in		std_logic; 
			CLK				: in		std_logic;
			MODE				: in		std_logic_vector (2 downto 0);
			CONTROL			: out		std_logic_vector (2 downto 0); -- LCD_RS, LCD_RW, LCD_E
			SF_D				: out		std_logic_vector (7 downto 4);  -- LCD data bus
			
			TEMP_IN			: in std_logic_vector(7 downto 0);
			TEMP_ADC_IN		: in std_logic_vector(9 downto 0);
			FAN_SPEED_IN	: in std_logic_vector(5 downto 0)
		);
	end component;

	component clock_generator
		port (
			-- Clock in ports
			CLK_IN_P      : in  std_logic;
			CLK_IN_N      : in  std_logic;
			
			-- Clock out ports
			CLK_OUT_200   : out std_logic;
			CLK_OUT_50    : out std_logic;
			--CLK_OUT_66    : out std_logic;
			
			-- Status and control signals
			RESET         : in  std_logic;
			LOCKED        : out std_logic
		 );
	end component;


	------------------------------------------------------------------------------
	-- Signal Declaration
	------------------------------------------------------------------------------

   -- clocks
	signal clk_200            : std_logic;
	signal clk_50            : std_logic;
	--signal clk_66             : std_logic;
	signal clk_locked         : std_logic;
	
	-- LCD stuff
	signal lcd_ctrl           : std_logic_vector(2 downto 0);
	signal lcd_db             : std_logic_vector(7 downto 4);
	
	-- ouput for the LCD
	signal temp_int		: std_logic_vector(7 downto 0);
	signal temp_adc_int	: std_logic_vector(9 downto 0);
	signal fan_speed_int	: std_logic_vector(5 downto 0);
	
	
begin

	------------------------------------------------------------------------------
	-- the central clock generator
	------------------------------------------------------------------------------
	
	U_CLOCK_GENERATOR : clock_generator
	port map (
		-- Clock in ports
		CLK_IN_P      => CLK_IN_P,
		CLK_IN_N      => CLK_IN_N,
		
		-- Clock out ports
		CLK_OUT_200   => clk_200,
		CLK_OUT_50   => clk_50,
		--CLK_OUT_66    => clk_66,
		
		-- Status and control signals
		RESET         => RESET,
		LOCKED        => clk_locked
	);


	------------------------------------------------------------------------------
	-- Fan regulator module
	------------------------------------------------------------------------------

	U_FAN_REGULATOR : fan_regulator
	port map (
		CLK			=> clk_50,
		RESET			=> RESET,
		FAN_PWM		=> SM_FAN_PWM,
		
		TEMP_OUT			=> temp_int,
		TEMP_ADC_OUT	=> temp_adc_int,
		FAN_SPEED_OUT	=> fan_speed_int
	);

	------------------------------------------------------------------------------
	-- the LCD module
	------------------------------------------------------------------------------
	
	U_LCD : lcd_control
		port map (
			RST			=> RESET,
			CLK			=> clk_50,
			MODE			=> "001",
			CONTROL		=> LCD_CTRL,
			SF_D			=> LCD_DB,
			
			TEMP_IN			=> temp_int,
			TEMP_ADC_IN		=> temp_adc_int,
			FAN_SPEED_IN	=> fan_speed_int
		);
		
	-- control signals for the lcd
	SF_D <= LCD_DB;
	LCD_E <= LCD_CTRL(0);
	LCD_RW <= LCD_CTRL(1);
	LCD_RS <= LCD_CTRL(2);


end Behavioral;

