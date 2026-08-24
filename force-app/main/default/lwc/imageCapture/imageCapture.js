import { LightningElement, track, api } from 'lwc';
import uploadCompressedImage from '@salesforce/apex/CompressedFileUploader.uploadCompressedImage';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';



export default class ImageCapture extends LightningElement {
    @track isCameraOn = false;
    @track photoURL;
    @api imageData; // Flow-accessible property
    videoStream;
    @api fileName;
   @api  fileId;
   @api captureTime
   selfieFile;
recordId;
    async startCamera() {
        try {
            this.isCameraOn = true;
            this.videoStream = await navigator.mediaDevices.getUserMedia({
                video: { facingMode: "environment" }
            });
            this.refs.videoElement.srcObject = this.videoStream;
            await new Promise(resolve => 
                this.refs.videoElement.onplaying = resolve
            );
        } catch (error) {
            console.error("Camera error:", error);
            this.isCameraOn = false;
        }
    }

   capturePhoto() {
    try {
        const video = this.template.querySelector('.video-feed');
        const canvas = this.template.querySelector('.hidden-canvas');
        const context = canvas.getContext('2d');

        canvas.width = video.videoWidth;
        canvas.height = video.videoHeight;
        context.drawImage(video, 0, 0, canvas.width, canvas.height);

        canvas.toBlob((blob) => {
            try {
                const reader = new FileReader();
                reader.readAsDataURL(blob);
                reader.onloadend = async () => {
                    try {
                        this.selfieFile = reader.result.split(',')[1];
                        this.photoURL = URL.createObjectURL(blob);
                        this.stopCamera();
                        //this.saveData();

                        const nameToUse = this.fileName || `Image_${new Date().toISOString().slice(0,10)}.jpg`;
                        this.captureTime = new Date().toLocaleTimeString();

                        // Upload the image
                        const result = await uploadCompressedImage({
                            base64Data: this.selfieFile,
                            fileName: nameToUse,
                            recordId: this.recordId,
                            captureTime: this.captureTime
                        });

                        this.fileId = result;
                        this.dispatchEvent(new FlowAttributeChangeEvent('fileId', this.fileId));
                    } catch (uploadError) {
    console.error('Upload failed:', uploadError);

    if (uploadError && uploadError.body) {
        console.error('Error Message:', uploadError.body.message);
        console.error('Error Stack Trace:', uploadError.body.stackTrace);
        console.error('Error Details:', uploadError.body);
    } else if (uploadError && uploadError.message) {
        console.error('General JS Error Message:', uploadError.message);
    } else {
        console.error('Unknown error:', JSON.stringify(uploadError));
    }
}
                };
            } catch (readerError) {
                console.error('Error reading blob as base64:', readerError);
            }
        }, 'image/jpeg', 0.7);

    } catch (err) {
        console.error('Error capturing photo:', err);
    }
}


    stopCamera() {
        if (this.videoStream) {
            this.videoStream.getTracks().forEach(track => track.stop());
        }
        this.isCameraOn = false;
    }

    dataURLtoBlob(dataURL) {
        const arr = dataURL.split(',');
        const mime = arr[0].match(/:(.*?);/)[1];
        const bstr = atob(arr[1]);
        let n = bstr.length;
        const u8arr = new Uint8Array(n);
        while(n--){
            u8arr[n] = bstr.charCodeAt(n);
        }
        return new Blob([u8arr], {type:mime});
    }
}