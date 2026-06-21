#include "Vcpu_elf_harness_top.h"
#include "elf_loader.h"
#include "verilated.h"

#include <array>
#include <cstdint>
#include <cstdio>
#include <exception>
#include <string>
#include <vector>

namespace {

constexpr uint32_t kSpmBytes = 1024 * 1024;
constexpr uint32_t kSpmBase = 0x80000000;
constexpr uint32_t kLineBytes = 64;
constexpr uint32_t kLineWords = 16;
constexpr uint32_t kNumLines = kSpmBytes / kLineBytes;
constexpr uint32_t kHaltInstr = 0x0000006f;
constexpr uint32_t kTohostPass = 1;
constexpr uint32_t kDisabledMailboxAddr = 0xfffffff0;

vluint64_t sim_time = 0;

struct HarnessOptions {
    uint32_t max_cycles = 10000;
    bool debug = false;
    bool show_console = true;
};

void eval(Vcpu_elf_harness_top& top) {
    top.eval();
}

void tick(Vcpu_elf_harness_top& top) {
    top.clk = 0;
    eval(top);
    sim_time++;
    top.clk = 1;
    eval(top);
    sim_time++;
}

void set_wide_line(Vcpu_elf_harness_top& top,
                   const std::array<uint32_t, kLineWords>& line) {
    for (uint32_t idx = 0; idx < kLineWords; idx++) {
        top.preload_req_wdata_i[idx] = line[idx];
    }
}

std::vector<std::array<uint32_t, kLineWords>> build_spm_lines(
    const ElfImage& image,
    std::vector<bool>& line_used,
    bool debug) {
    std::vector<uint8_t> mem(kSpmBytes, 0);
    line_used.assign(kNumLines, false);

    for (const auto& section : image.sections) {
        if (debug) {
            std::fprintf(stderr,
                         "[ELF] section %-16s addr=0x%08x size=0x%08x%s\n",
                         section.name.c_str(),
                         section.address,
                         section.size,
                         section.nobits ? " nobits" : "");
        }

        const uint32_t section_offset = section.address - kSpmBase;
        for (uint32_t idx = 0; idx < section.size; idx++) {
            mem[section_offset + idx] = section.data[idx];
        }

        const uint32_t first_line = section_offset / kLineBytes;
        const uint32_t last_line =
            (section_offset + section.size - 1) / kLineBytes;
        for (uint32_t line = first_line; line <= last_line; line++) {
            line_used[line] = true;
        }
    }

    std::vector<std::array<uint32_t, kLineWords>> lines(kNumLines);
    for (uint32_t line = 0; line < kNumLines; line++) {
        lines[line].fill(0);
        const uint32_t base = line * kLineBytes;
        for (uint32_t word = 0; word < kLineWords; word++) {
            const uint32_t off = base + word * 4;
            lines[line][word] =
                static_cast<uint32_t>(mem[off]) |
                (static_cast<uint32_t>(mem[off + 1]) << 8) |
                (static_cast<uint32_t>(mem[off + 2]) << 16) |
                (static_cast<uint32_t>(mem[off + 3]) << 24);
        }
    }

    return lines;
}

void init_inputs(Vcpu_elf_harness_top& top) {
    top.clk = 0;
    top.reset_n = 0;
    top.cpu_enable_i = 0;
    top.software_interrupt_pending_i = 0;
    top.timer_interrupt_pending_i = 0;
    top.external_interrupt_pending_i = 0;
    top.preload_req_valid_i = 0;
    top.preload_req_line_addr_i = 0;
    top.preload_resp_ready_i = 1;
    top.host_tohost_addr_i = kDisabledMailboxAddr;
    top.host_console_addr_i = kDisabledMailboxAddr;
    std::array<uint32_t, kLineWords> zero_line{};
    zero_line.fill(0);
    set_wide_line(top, zero_line);
}

void reset_dut(Vcpu_elf_harness_top& top) {
    top.reset_n = 0;
    top.cpu_enable_i = 0;
    for (int i = 0; i < 5; i++) {
        tick(top);
    }
    top.reset_n = 1;
    for (int i = 0; i < 2; i++) {
        tick(top);
    }
}

void preload_line(Vcpu_elf_harness_top& top,
                  uint32_t line_addr,
                  const std::array<uint32_t, kLineWords>& line) {
    top.preload_req_line_addr_i = (kSpmBase / kLineBytes) + line_addr;
    set_wide_line(top, line);
    top.preload_req_valid_i = 1;
    top.preload_resp_ready_i = 1;
    eval(top);

    uint32_t wait_cycles = 0;
    while (!top.preload_req_ready_o) {
        tick(top);
        if (++wait_cycles > 1000) {
            throw std::runtime_error("preload request timeout");
        }
    }

    tick(top);
    top.preload_req_valid_i = 0;
    eval(top);

    wait_cycles = 0;
    while (!top.preload_resp_valid_o) {
        tick(top);
        if (++wait_cycles > 1000) {
            throw std::runtime_error("preload response timeout");
        }
    }
    if (top.preload_resp_error_o) {
        throw std::runtime_error("preload response error");
    }
    tick(top);
}

void preload_image(Vcpu_elf_harness_top& top,
                   const std::vector<std::array<uint32_t, kLineWords>>& lines,
                   const std::vector<bool>& line_used,
                   bool debug) {
    uint32_t count = 0;
    for (uint32_t line = 0; line < lines.size(); line++) {
        if (!line_used[line]) {
            continue;
        }
        preload_line(top, line, lines[line]);
        count++;
    }
    if (debug) {
        std::fprintf(stderr, "[LOAD] preloaded %u cachelines\n", count);
    }
}

bool find_symbol(const ElfImage& image,
                 const std::string& name,
                 uint32_t& address) {
    for (const auto& symbol : image.symbols) {
        if (symbol.name == name) {
            address = symbol.address;
            return true;
        }
    }
    return false;
}

int decode_tohost_status(uint32_t value) {
    if (value == kTohostPass) {
        std::fprintf(stderr, "[PASS] tohost=0x%08x\n", value);
        return 0;
    }

    if ((value & 1U) != 0) {
        const uint32_t exit_code = value >> 1;
        std::fprintf(stderr,
                     "[FAIL] tohost=0x%08x exit_code=%u\n",
                     value,
                     exit_code);
        return exit_code == 0 ? 1 : static_cast<int>(exit_code);
    }

    std::fprintf(stderr,
                 "[FAIL] unexpected tohost value=0x%08x\n",
                 value);
    return 1;
}

int run(Vcpu_elf_harness_top& top,
        uint32_t max_cycles,
        bool monitor_tohost,
        bool debug,
        bool show_console) {
    uint32_t halt_count = 0;
    uint32_t halt_pc = 0;

    top.cpu_enable_i = 1;
    for (uint32_t cycle = 0; cycle < max_cycles; cycle++) {
        tick(top);

        if (monitor_tohost && top.host_tohost_valid_o &&
            top.host_tohost_value_o != 0) {
            top.cpu_enable_i = 0;
            if (debug) {
                std::fprintf(stderr,
                             "[HALT] tohost write cycles=%u\n",
                             cycle);
            }
            return decode_tohost_status(top.host_tohost_value_o);
        }

        if (top.host_console_valid_o && show_console) {
            std::fputc(static_cast<int>(top.host_console_char_o), stdout);
            std::fflush(stdout);
        }

        if (top.debug_commit_valid_o) {
            if (debug) {
                std::fprintf(stderr,
                             "[COMMIT] pc=0x%08x instr=0x%08x rf_we=%u "
                             "rd=%u wdata=0x%08x exc=%u irq=%u "
                             "fetch_pc=0x%08x\n",
                             top.debug_commit_pc_o,
                             top.debug_commit_instr_o,
                             top.debug_rf_we_o,
                             top.debug_rf_waddr_o,
                             top.debug_rf_wdata_o,
                             top.debug_commit_exception_o,
                             top.debug_commit_interrupt_o,
                             top.debug_fetch_pc_o);

                if (top.debug_commit_exception_o) {
                    std::fprintf(stderr,
                                 "[WARN] exception committed at pc=0x%08x\n",
                                 top.debug_commit_pc_o);
                }
            }

            if (top.debug_commit_instr_o == kHaltInstr) {
                if (halt_count != 0 && halt_pc == top.debug_commit_pc_o) {
                    halt_count++;
                } else {
                    halt_pc = top.debug_commit_pc_o;
                    halt_count = 1;
                }
            } else {
                halt_count = 0;
            }

            if (halt_count >= 3) {
                top.cpu_enable_i = 0;
                if (debug) {
                    std::fprintf(stderr,
                                 "[HALT] self-loop pc=0x%08x cycles=%u\n",
                                 halt_pc,
                                 cycle);
                }
                return 0;
            }
        }
    }

    std::fprintf(stderr, "[FAIL] timeout after %u cycles\n", max_cycles);
    return 1;
}

HarnessOptions parse_options(int argc, char** argv) {
    HarnessOptions options;
    for (int idx = 2; idx < argc; idx++) {
        const std::string arg(argv[idx]);
        const std::string prefix = "--max-cycles=";
        if (arg.rfind(prefix, 0) == 0) {
            options.max_cycles =
                static_cast<uint32_t>(std::stoul(arg.substr(prefix.size())));
        } else if (arg == "--debug" || arg == "--log") {
            options.debug = true;
            options.show_console = false;
        } else if (arg == "--run" || arg == "--quiet") {
            options.debug = false;
            options.show_console = true;
        } else if (arg == "--show-console") {
            options.show_console = true;
        } else if (arg == "--hide-console") {
            options.show_console = false;
        } else {
            throw std::runtime_error("unknown harness option: " + arg);
        }
    }
    return options;
}

}  // namespace

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    if (argc < 2) {
        std::fprintf(stderr,
                     "usage: %s <program.elf> [--max-cycles=N] "
                     "[--run|--quiet|--debug] "
                     "[--show-console|--hide-console]\n",
                     argv[0]);
        return 1;
    }

    try {
        const std::string elf_path(argv[1]);
        const HarnessOptions options = parse_options(argc, argv);
        ElfImage image = load_elf32_sections(elf_path, kSpmBase, kSpmBytes);

        if (options.debug) {
            std::fprintf(stderr,
                         "[ELF] path=%s entry=0x%08x sections=%zu\n",
                         elf_path.c_str(),
                         image.entry,
                         image.sections.size());
            if (image.entry != kSpmBase) {
                std::fprintf(stderr,
                             "[WARN] ELF entry is not reset PC 0x%08x\n",
                             kSpmBase);
            }
        }

        uint32_t tohost_addr = kDisabledMailboxAddr;
        const bool monitor_tohost = find_symbol(image, "tohost", tohost_addr);
        if (options.debug) {
            if (monitor_tohost) {
                std::fprintf(stderr, "[ELF] tohost=0x%08x\n", tohost_addr);
            } else {
                std::fprintf(stderr,
                             "[WARN] ELF has no tohost symbol; using "
                             "self-loop halt fallback only\n");
            }
        }

        uint32_t console_addr = kDisabledMailboxAddr;
        const bool has_console = find_symbol(image,
                                             "console_putchar",
                                             console_addr);
        if (options.debug) {
            if (has_console) {
                std::fprintf(stderr,
                             "[ELF] console_putchar=0x%08x\n",
                             console_addr);
            } else {
                std::fprintf(stderr,
                             "[WARN] ELF has no console_putchar symbol; "
                             "stdout mailbox disabled\n");
            }
        }

        std::vector<bool> line_used;
        auto lines = build_spm_lines(image, line_used, options.debug);

        Vcpu_elf_harness_top top;
        init_inputs(top);
        top.host_tohost_addr_i = tohost_addr;
        top.host_console_addr_i = console_addr;
        reset_dut(top);
        preload_image(top, lines, line_used, options.debug);
        const int status = run(top,
                               options.max_cycles,
                               monitor_tohost,
                               options.debug,
                               options.show_console);
        top.final();
        return status;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "[FAIL] %s\n", e.what());
        return 1;
    }
}
