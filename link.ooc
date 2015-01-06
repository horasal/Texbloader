import io/BinarySequence

Link: class{
    path: String

    init: func(buffer: BinarySequenceReader){
        if(buffer u32() != 0x4c494e4b){
            Exception new("Invalid Link file") throw()
        }
        path = buffer pascalString(4)
    }
}
