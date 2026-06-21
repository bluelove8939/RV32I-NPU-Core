#include "elf_loader.h"

#include <array>
#include <fstream>
#include <stdexcept>

namespace {

constexpr uint32_t SHT_NOBITS = 8;
constexpr uint32_t SHT_SYMTAB = 2;
constexpr uint32_t SHT_DYNSYM = 11;
constexpr uint32_t SHF_ALLOC = 0x2;

uint16_t read_u16(const std::vector<uint8_t>& bytes, size_t off) {
    if (off + 2 > bytes.size()) {
        throw std::runtime_error("ELF read past end");
    }
    return static_cast<uint16_t>(bytes[off]) |
           (static_cast<uint16_t>(bytes[off + 1]) << 8);
}

uint32_t read_u32(const std::vector<uint8_t>& bytes, size_t off) {
    if (off + 4 > bytes.size()) {
        throw std::runtime_error("ELF read past end");
    }
    return static_cast<uint32_t>(bytes[off]) |
           (static_cast<uint32_t>(bytes[off + 1]) << 8) |
           (static_cast<uint32_t>(bytes[off + 2]) << 16) |
           (static_cast<uint32_t>(bytes[off + 3]) << 24);
}

std::vector<uint8_t> read_file(const std::string& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        throw std::runtime_error("cannot open ELF file: " + path);
    }
    return std::vector<uint8_t>(std::istreambuf_iterator<char>(in),
                                std::istreambuf_iterator<char>());
}

std::string section_name(const std::vector<uint8_t>& strtab,
                         uint32_t name_off) {
    if (name_off >= strtab.size()) {
        return "";
    }

    size_t end = name_off;
    while (end < strtab.size() && strtab[end] != 0) {
        end++;
    }
    return std::string(reinterpret_cast<const char*>(&strtab[name_off]),
                       end - name_off);
}

}  // namespace

ElfImage load_elf32_sections(const std::string& path,
                             uint32_t spm_base,
                             uint32_t spm_size) {
    std::vector<uint8_t> bytes = read_file(path);
    if (bytes.size() < 52) {
        throw std::runtime_error("ELF file is too small: " + path);
    }
    if (bytes[0] != 0x7f || bytes[1] != 'E' || bytes[2] != 'L' ||
        bytes[3] != 'F') {
        throw std::runtime_error("not an ELF file: " + path);
    }
    if (bytes[4] != 1 || bytes[5] != 1) {
        throw std::runtime_error("only ELF32 little-endian files are supported");
    }

    const uint16_t machine = read_u16(bytes, 18);
    if (machine != 243) {
        throw std::runtime_error("ELF machine is not RISC-V");
    }

    const uint32_t entry = read_u32(bytes, 24);
    const uint32_t shoff = read_u32(bytes, 32);
    const uint16_t shentsize = read_u16(bytes, 46);
    const uint16_t shnum = read_u16(bytes, 48);
    const uint16_t shstrndx = read_u16(bytes, 50);
    if (shentsize < 40 || shnum == 0 || shstrndx >= shnum) {
        throw std::runtime_error("unsupported or missing ELF section table");
    }
    if (static_cast<uint64_t>(shoff) +
            static_cast<uint64_t>(shentsize) * shnum >
        bytes.size()) {
        throw std::runtime_error("ELF section table is out of range");
    }

    const size_t shstr_off = shoff + static_cast<size_t>(shentsize) * shstrndx;
    const uint32_t shstr_file_off = read_u32(bytes, shstr_off + 16);
    const uint32_t shstr_size = read_u32(bytes, shstr_off + 20);
    if (static_cast<uint64_t>(shstr_file_off) + shstr_size > bytes.size()) {
        throw std::runtime_error("ELF section string table is out of range");
    }
    std::vector<uint8_t> shstr(bytes.begin() + shstr_file_off,
                               bytes.begin() + shstr_file_off + shstr_size);

    ElfImage image;
    image.entry = entry;

    for (uint16_t idx = 0; idx < shnum; idx++) {
        const size_t off = shoff + static_cast<size_t>(shentsize) * idx;
        const uint32_t name = read_u32(bytes, off + 0);
        const uint32_t type = read_u32(bytes, off + 4);
        const uint32_t flags = read_u32(bytes, off + 8);
        const uint32_t addr = read_u32(bytes, off + 12);
        const uint32_t file_off = read_u32(bytes, off + 16);
        const uint32_t size = read_u32(bytes, off + 20);

        if ((flags & SHF_ALLOC) == 0 || size == 0) {
            continue;
        }
        if (addr < spm_base ||
            static_cast<uint64_t>(addr) + size >
                static_cast<uint64_t>(spm_base) + spm_size) {
            throw std::runtime_error("ELF section does not fit in SPM: " +
                                     section_name(shstr, name));
        }

        ElfSectionImage section;
        section.name = section_name(shstr, name);
        section.address = addr;
        section.size = size;
        section.nobits = (type == SHT_NOBITS);
        section.data.assign(size, 0);

        if (!section.nobits) {
            if (static_cast<uint64_t>(file_off) + size > bytes.size()) {
                throw std::runtime_error("ELF section data is out of range: " +
                                         section.name);
            }
            section.data.assign(bytes.begin() + file_off,
                                bytes.begin() + file_off + size);
        }

        image.sections.push_back(std::move(section));
    }

    for (uint16_t idx = 0; idx < shnum; idx++) {
        const size_t off = shoff + static_cast<size_t>(shentsize) * idx;
        const uint32_t type = read_u32(bytes, off + 4);
        const uint32_t file_off = read_u32(bytes, off + 16);
        const uint32_t size = read_u32(bytes, off + 20);
        const uint32_t link = read_u32(bytes, off + 24);
        const uint32_t entsize = read_u32(bytes, off + 36);

        if (type != SHT_SYMTAB && type != SHT_DYNSYM) {
            continue;
        }
        if (entsize < 16 || size == 0 || link >= shnum) {
            continue;
        }
        if (static_cast<uint64_t>(file_off) + size > bytes.size()) {
            throw std::runtime_error("ELF symbol table is out of range");
        }

        const size_t strtab_shoff =
            shoff + static_cast<size_t>(shentsize) * link;
        const uint32_t strtab_file_off = read_u32(bytes, strtab_shoff + 16);
        const uint32_t strtab_size = read_u32(bytes, strtab_shoff + 20);
        if (static_cast<uint64_t>(strtab_file_off) + strtab_size >
            bytes.size()) {
            throw std::runtime_error("ELF symbol string table is out of range");
        }
        std::vector<uint8_t> strtab(bytes.begin() + strtab_file_off,
                                    bytes.begin() + strtab_file_off +
                                        strtab_size);

        const uint32_t count = size / entsize;
        for (uint32_t sym_idx = 0; sym_idx < count; sym_idx++) {
            const size_t sym_off = file_off + static_cast<size_t>(entsize) *
                                                  sym_idx;
            const uint32_t name = read_u32(bytes, sym_off + 0);
            const uint32_t value = read_u32(bytes, sym_off + 4);
            const uint32_t sym_size = read_u32(bytes, sym_off + 8);
            std::string sym_name = section_name(strtab, name);

            if (sym_name.empty()) {
                continue;
            }

            ElfSymbol symbol;
            symbol.name = std::move(sym_name);
            symbol.address = value;
            symbol.size = sym_size;
            image.symbols.push_back(std::move(symbol));
        }
    }

    return image;
}
