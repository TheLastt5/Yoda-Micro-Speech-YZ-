import tensorflow as tf
import numpy as np
import os

# --- AYARLAR ---
MODEL_PATH = "micro_speech.tflite" 
WEIGHTS_FILE = "weights.hex"
BIAS_FILE = "biases.hex"

def int8_to_hex(value):
    # DÜZELTME: int(value) ekleyerek numpy tipinden kurtarıyoruz
    return "{:02X}".format(int(value) & 0xff)

def int32_to_hex(value):
    # DÜZELTME: int(value) ekleyerek OverflowError hatasını çözüyoruz
    return "{:08X}".format(int(value) & 0xffffffff)

def main():
    if not os.path.exists(MODEL_PATH):
        print(f"HATA: '{MODEL_PATH}' dosyası bulunamadı. Dosya adını kontrol et.")
        return

    try:
        interpreter = tf.lite.Interpreter(model_path=MODEL_PATH)
        interpreter.allocate_tensors()
    except Exception as e:
        print(f"HATA: Model yüklenirken sorun çıktı! ({e})")
        return

    tensor_details = interpreter.get_tensor_details()
    
    found_weights = False
    found_bias = False
    
    print(f"--- '{MODEL_PATH}' Analiz Ediliyor ---")

    for tensor in tensor_details:
        name = tensor['name']
        shape = tensor['shape']
        
        # 1. AĞIRLIKLARI BUL (first_weights/read)
        # Ekran görüntüne göre isim 'first_weights/read' ve boyut [1,10,8,8]
        if ("weights" in name or "read" in name) and np.prod(shape) == 640:
            print(f"BULDUM! Ağırlık Katmanı: {name} (Boyut: {shape})")
            
            data = interpreter.tensor(tensor['index'])()
            flat_data = data.flatten()
            
            with open(WEIGHTS_FILE, "w") as f:
                for val in flat_data:
                    f.write(int8_to_hex(val) + "\n")
            
            print(f" -> {WEIGHTS_FILE} oluşturuldu ({len(flat_data)} satır).")
            found_weights = True

        # 2. BIASLARI BUL (Conv2D_bias)
        # Ekran görüntüne göre isim 'Conv2D_bias' ve boyut [8]
        if "bias" in name and np.prod(shape) == 8:
             print(f"BULDUM! Bias Katmanı: {name} (Boyut: {shape})")
             
             data = interpreter.tensor(tensor['index'])()
             flat_data = data.flatten()
             
             with open(BIAS_FILE, "w") as f:
                 for val in flat_data:
                     f.write(int32_to_hex(val) + "\n")
                     
             print(f" -> {BIAS_FILE} oluşturuldu ({len(flat_data)} satır).")
             found_bias = True

    if found_weights and found_bias:
        print("\nTEBRİKLER! Hex dosyaların hazır. Simülasyona geçebilirsin.")
    else:
        print("\nUYARI: Dosyalar tam oluşmadı. Model dosyasının doğru olduğundan emin ol.")

if __name__ == "__main__":
    main()