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
		USER_LED            : out std_logic_vector (7 downto 0)
		
	);
end topl;

architecture Behavioral of topl is

	------------------------------------------------------------------------------
	-- Component Declaration
	------------------------------------------------------------------------------
  
	component fan_regulator
		port (
			CLK_66      : in  STD_LOGIC;
			RESET       : in  STD_LOGIC;
			DISPLAY     : out STD_LOGIC_VECTOR (7 downto 0);
			FAN_PWM		: out STD_LOGIC
		);
	end component;

	component clock_generator
		port (
			-- Clock in ports
			CLK_IN_P      : in  std_logic;
			CLK_IN_N      : in  std_logic;
			
			-- Clock out ports
			CLK_OUT_200   : out std_logic;
			CLK_OUT_125   : out std_logic;
			CLK_OUT_66    : out std_logic;
			
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
	signal clk_125            : std_logic;
	signal clk_66             : std_logic;
	signal clk_locked         : std_logic;
	
	
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
		CLK_OUT_125   => clk_125,
		CLK_OUT_66    => clk_66,
		
		-- Status and control signals
		RESET         => RESET,
		LOCKED        => clk_locked
	);


	------------------------------------------------------------------------------
	-- Signal Declaration
	------------------------------------------------------------------------------
	U_FAN_REGULATOR : fan_regulator
	port map (
		CLK_66		=> clk_66,
		RESET			=> RESET,
		DISPLAY		=> USER_LED,
		FAN_PWM		=> SM_FAN_PWM
	);


end Behavioral;

