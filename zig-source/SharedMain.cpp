#include "DxcCInterface.h"

int main(void) 
{ 
    // Absolutely no clue why we need to do this, but without it the static library will not export ANY symbols. 
    // I guess we have to show the compiler we're actually using static DXC or it'll optimize it into nothingness.
    DxcCompiler comp = DxcInitialize(); 
    DxcFinalize(comp); 
}

