#ifndef NMTA_ELF_LOADER_H
#define NMTA_ELF_LOADER_H

#include <cstdint>
#include <string>
#include <vector>

struct ElfSectionImage {
    std::string name;
    uint32_t address = 0;
    uint32_t size = 0;
    std::vector<uint8_t> data;
    bool nobits = false;
};

struct ElfSymbol {
    std::string name;
    uint32_t address = 0;
    uint32_t size = 0;
};

struct ElfImage {
    uint32_t entry = 0;
    std::vector<ElfSectionImage> sections;
    std::vector<ElfSymbol> symbols;
};

ElfImage load_elf32_sections(const std::string& path,
                             uint32_t spm_base,
                             uint32_t spm_size);

#endif
