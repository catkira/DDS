import numpy as np
import matplotlib.pyplot as plt
import matplotlib


output = np.loadtxt("out.txt")
output_cos = np.loadtxt("out_cos.txt")
output_model = np.loadtxt("out_model.txt")
output_model_cos = np.loadtxt("out_model_cos.txt")
length = min(len(output),len(output_model),len(output_model_cos),len(output_cos))
x = np.arange(1,length)
sin = output[1:length]
sin_model = output_model[1:length]
cos = output_cos[1:length]
cos_model = output_model_cos[1:length]
plt.plot(x, sin, x, sin_model, x, cos, x, cos_model)
plt.show()

