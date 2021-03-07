import numpy as np
import matplotlib.pyplot as plt
import matplotlib


output = np.loadtxt("out.txt")
output_model = np.loadtxt("out_model.txt")
length = min(len(output),len(output_model))
x = np.arange(1,length)
y1 = output[1:length]
y2 = output_model[1:length]
plt.plot(x, y1, x, y2)
plt.show()

