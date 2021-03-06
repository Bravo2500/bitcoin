----------------------------------------------------------------------------------
-- Company:
-- Engineer:
--
-- Create Date:    22:18:21 05/28/2011
-- Design Name:
-- Module Name:    top - Behavioral
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
--use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.VComponents.all;

library work;
use work.btc.all;

entity top is
  port (
         clk_in_p : in  STD_LOGIC;
         clk_in_n : in  STD_LOGIC;

         tx     : out STD_LOGIC;
         rx     : in  STD_LOGIC;
         leds   : out STD_LOGIC_VECTOR(3 downto 0)
       );
end top;

architecture Behavioral of top is
  constant DEPTH : integer := 1;

  COMPONENT miner
    generic ( DEPTH : integer );
    PORT(
          clk : IN std_logic;
          step : IN std_logic_vector(5 downto 0);
          data : IN std_logic_vector(95 downto 0);
          state : IN  STD_LOGIC_VECTOR (255 downto 0);
          nonce : IN std_logic_vector(31 downto 0);
          hit : OUT std_logic
        );
  END COMPONENT;

  COMPONENT uart
    PORT(
          clk : IN std_logic;
          rx : IN std_logic;
          txdata : IN std_logic_vector(48 downto 0);
          txwidth : IN std_logic_vector(5 downto 0);
          txstrobe : IN std_logic;
          txbusy : OUT std_logic;
          tx : OUT std_logic;
          rxdata : OUT std_logic_vector(7 downto 0);
          rxstrobe : OUT std_logic
        );
  END COMPONENT;

  COMPONENT dcm
    PORT(
          CLK_IN1_P : in std_logic;
          CLK_IN1_N : in std_logic;
          CLK_OUT1 : out std_logic;
          LOCKED : out std_logic
        );
  END COMPONENT;

  signal clk : std_logic;
  signal clk_dcmin : std_logic;
  signal clk_dcmout : std_logic;

  signal data : std_logic_vector(95 downto 0);
  signal state : std_logic_vector(255 downto 0);
  signal load : std_logic_vector(343 downto 0);
  signal loadctr : std_logic_vector(5 downto 0);
  signal loading : std_logic := '0';

  signal nonces : slv32;
  signal curnonces : slv32;
  signal hits : std_logic_vector(WIDTH-1 downto 0);
  signal hit  : std_logic;
  signal exhausted : std_logic;

  signal txdata : std_logic_vector(48 downto 0);
  signal txwidth : std_logic_vector(5 downto 0);
  signal txstrobe : std_logic;
  signal rxdata : std_logic_vector(7 downto 0);
  signal rxstrobe : std_logic;
  signal step : std_logic_vector(5 downto 0) := "000000";
  signal locked : std_logic;
begin

  inst_dcm : dcm
  port map (
             -- Clock in ports
             CLK_IN1_P => clk_in_p,
             CLK_IN1_N => clk_in_n,
             -- Clock out ports
             CLK_OUT1 => clk,
             -- Status and control signals
             LOCKED => locked
           );

  miners: for i in 0 to WIDTH-1 generate
  begin
    curnonces(i) <= nonces(i) - 2 * 2 ** DEPTH;

    inst_miner: miner
    generic map ( DEPTH => DEPTH )
    port map (
               clk => clk,
               step => step,
               data => data,
               state => state,

               nonce => nonces(i),
               hit => hits(i)
             );
  end generate;

  serial: uart
  port map (
             clk => clk,
             tx => tx,
             rx => rx,
             txdata => txdata,
             txwidth => txwidth,
             txstrobe => txstrobe,
             txbusy => open,
             rxdata => rxdata,
             rxstrobe => rxstrobe
           );

  leds(3) <= locked;
  hit <= or_slv(hits);
  exhausted <= nonces_exhausted(nonces);

  process(clk)
  begin
    if rising_edge(clk) then

      --Increment stop/nonce depending on DEPTH
      step <= step + 1;
      if conv_integer(step) = 2 ** (6 - DEPTH) - 1 then
        step <= "000000";
        for i in 0 to WIDTH-1 loop
          nonces(i) <= nonces(i) + WIDTH;
        end loop;
      end if;

      --IO/Control
      txstrobe <= '0';
      if rxstrobe = '1' then
        --Received some data
        if loading = '1' then
          --Is in the 'loading' stage
          if loadctr = "101011" then
            --Finish loading 'data'
            leds(2 downto 0) <= "100";
            state <= load(343 downto 88);
            data <= load(87 downto 0) & rxdata;
            for i in 0 to WIDTH-1 loop
              nonces(i) <= std_logic_vector(to_unsigned(i,32));
            end loop;
            --Command=1
            txdata <= "1111111111111111111111111111111111111111000000010";
            txwidth <= "001010";
            txstrobe <= '1';
            loading <= '0';
          else
            --Load 'state'
            leds(2 downto 0) <= "101";
            load(343 downto 8) <= load(335 downto 0);
            load(7 downto 0) <= rxdata;
            loadctr <= loadctr + 1;
          end if;
        else
          --Not 'loading'
          if rxdata = "00000000" then
            --FPGA existence check?
            leds(2 downto 0) <= "110";
            --Command=0
            txdata <= "1111111111111111111111111111111111111111000000000";
            txwidth <= "001010";
            txstrobe <= '1';
          elsif rxdata = "00000001" then
            --Start 'loading' data
            leds(2 downto 0) <= "111";
            loadctr <= "000000";
            loading <= '1';
          end if;
        end if;
      elsif hit = '1' then
        --Found a valid nonce
        leds(2 downto 0) <= "010";
        for i in 0 to WIDTH-1 loop
          --Command=2
          if hits(i) = '1' then
            txdata <= curnonces(i)(7 downto 0) & "01" & curnonces(i)(15 downto 8) & "01" & curnonces(i)(23 downto 16) & "01" & curnonces(i)(31 downto 24) & "01000000100";
          end if;
        end loop;
        txwidth <= "110010";
        txstrobe <= '1';
      elsif exhausted = '1' and step = "000000" then
        --Exhausted search space
        leds(2 downto 0) <= "011";
        --Command=3
        txdata <= "1111111111111111111111111111111111111111000000110";
        txwidth <= "110010";
        txstrobe <= '1';
      end if;
    end if;
  end process;

end Behavioral;

