fn process_data(data: SIMD[f32, 8]):
    let threshold: Float32 = 0.5
    if data[0] > threshold:
        print("Mojo high signal")
    else:
        print("Mojo low signal")