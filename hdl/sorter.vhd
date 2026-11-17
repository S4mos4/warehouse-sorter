library ieee;
use ieee.std_logic_1164.all;

entity sorter is
    port (
        clk           : in  std_logic;
        reset         : in  std_logic;
        entry_request : in  std_logic;
        select_lane   : in  std_logic;
        entry_ready   : out std_logic;
        route_a       : out std_logic;
        route_b       : out std_logic
    );
end entity;

architecture rtl of sorter is
    type state_t is (idle, routing_a, routing_b);
    signal state, next_state : state_t;
begin
    -- Accept a request on a rising edge when ready and reset is low.
    -- A lane selection of '0' routes to A. A selection of '1' routes to B.
    process (clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= idle;
            else
                state <= next_state;
            end if;
        end if;
    end process;

    process (all)
    begin
        next_state <= idle;
        case state is
            when idle =>
                if entry_request = '1' then
                    if select_lane = '0' then
                        next_state <= routing_a;
                    elsif select_lane = '1' then
                        next_state <= routing_b;
                    end if;
                end if;
            when routing_a | routing_b =>
                next_state <= idle;
        end case;
    end process;

    -- Moore outputs only depend on the registered state.
    entry_ready <= '1' when state = idle else '0';
    route_a <= '1' when state = routing_a else '0';
    route_b <= '1' when state = routing_b else '0';
end architecture;
