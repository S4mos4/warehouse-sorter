library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;

entity tb_sorter is
end entity;

architecture test of tb_sorter is
    -- Rising edges occur at whole simulated milliseconds.
    constant half_period : time := 500 us;
    constant demo_end_ms : natural := 2600;
    constant test_end_ms : natural := 2624;

    signal clk : std_logic := '1';
    signal reset : std_logic := '1';
    signal entry_request, select_lane : std_logic := '0';
    signal entry_ready, route_a, route_b : std_logic;
    signal exit_a, exit_b, tick : std_logic := '0';
begin
    clk <= not clk after half_period;

    dut : entity work.sorter
        port map (
            clk           => clk,
            reset         => reset,
            entry_request => entry_request,
            select_lane   => select_lane,
            entry_ready   => entry_ready,
            route_a       => route_a,
            route_b       => route_b
        );

    stimulus : process
        procedure drive_before(constant time_ms : in positive) is
        begin
            wait for time_ms * 1 ms - half_period - now;
        end procedure;

        procedure request_at(
            constant time_ms : in positive;
            constant lane     : in std_logic
        ) is
        begin
            drive_before(time_ms);
            select_lane <= lane;
            entry_request <= '1';
            wait until falling_edge(clk);
            entry_request <= '0';
        end procedure;

        procedure pulse_at(
            constant time_ms : in positive;
            signal sensor     : out std_logic
        ) is
        begin
            drive_before(time_ms);
            sensor <= '1';
            wait until falling_edge(clk);
            sensor <= '0';
        end procedure;
    begin
        drive_before(1);
        select_lane <= '1';
        entry_request <= '1'; -- Reset must suppress a request even when idle.
        drive_before(2);
        entry_request <= '0';
        reset <= '0';
        request_at(100, '0');
        request_at(101, '1'); -- The gate is busy, so this request is ignored.
        request_at(150, '1');
        pulse_at(350, exit_b);
        pulse_at(400, exit_a);
        request_at(500, '0');
        pulse_at(1499, tick);
        pulse_at(1500, tick);
        pulse_at(2500, tick);
        pulse_at(2600, exit_a);

        -- Reset while routing and hold it through the following idle cycle.
        request_at(2620, '0');
        drive_before(2621);
        reset <= '1';
        entry_request <= '1';
        drive_before(2623);
        reset <= '0';
        request_at(2623, '1');
        wait;
    end process;

    check_and_log : process
        file trace : text open write_mode is "trace.csv";
        variable row : line;
        variable time_ms : natural;
        variable expected_a, expected_b : std_logic;

        procedure log_event(
            constant stamp : in natural;
            constant event_and_lane : in string
        ) is
        begin
            write(row, stamp);
            write(row, string'(","));
            write(row, event_and_lane);
            writeline(trace, row);
        end procedure;
    begin
        write(row, string'("time_ms,event,lane"));
        writeline(trace, row);

        loop
            wait until rising_edge(clk);
            wait for 1 ns; -- Settle the state register and its decoded outputs.
            time_ms := now / 1 ms;
            expected_a := '0';
            expected_b := '0';
            case time_ms is
                when 100 | 500 | 2620 => expected_a := '1';
                when 150 | 2623 => expected_b := '1';
                when others => null;
            end case;
            assert route_a = expected_a and route_b = expected_b
                report "Unexpected route output at " & natural'image(time_ms) & " ms"
                severity failure;
            assert entry_ready = not (expected_a or expected_b)
                report "Unexpected ready output at " & natural'image(time_ms) & " ms"
                severity failure;

            if time_ms <= demo_end_ms then
                if route_a = '1' then
                    log_event(time_ms, "ENTRY,A");
                elsif route_b = '1' then
                    log_event(time_ms, "ENTRY,B");
                end if;
                if exit_a = '1' then
                    log_event(time_ms, "EXIT,A");
                end if;
                if exit_b = '1' then
                    log_event(time_ms, "EXIT,B");
                end if;
                if tick = '1' then
                    log_event(time_ms, "TICK,");
                end if;
            end if;

            exit when time_ms = test_end_ms;
        end loop;

        file_close(trace);
        report "Sorter routing, busy handling, and reset checks passed." severity note;
        std.env.finish;
    end process;
end architecture;
