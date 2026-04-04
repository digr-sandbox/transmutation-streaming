package com.transmutation.core;
import java.util.*;

public class DocumentProcessor {
    private final String processorId;
    
    public DocumentProcessor(String id) {
        this.processorId = id;
    }

    @Override
    public Result process(byte[] inputData) throws ProcessingException {
        if (inputData == null) throw new ProcessingException("Empty data");
        System.out.println("Processing in Java: " + processorId);
        return new Result(true, "Success");
    }
}