package com.mycroclean.rfid;

import android.app.*;
import android.os.Bundle;
import android.os.Handler;
import android.bluetooth.*;
import android.webkit.*;
import android.net.Uri;
import java.io.*;
import java.util.*;
import org.json.JSONArray;
import org.json.JSONObject;

public class ReaderApp extends Activity {
    private static final String HOME = "https://gestionale.mycroclean.com";
    private static final UUID RFID = UUID.fromString("2ad8a392-0e49-e52c-a6d2-60834c012263");
    private WebView web;
    private volatile BluetoothSocket active;
    private final Handler handler = new Handler();
    private int generation;
    private static boolean trusted(Uri uri) {
        return "https".equals(uri.getScheme()) && "gestionale.mycroclean.com".equals(uri.getHost())
            && (uri.getPort() == -1 || uri.getPort() == 443);
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        web = new WebView(this);
        setContentView(web);
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(false);
        web.getSettings().setAllowContentAccess(false);
        web.getSettings().setUserAgentString(web.getSettings().getUserAgentString()+" MycrocleanRFID/1");
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri uri = req.getUrl();
                if ("mycro-rfid".equals(uri.getScheme())) {
                    if (req.isForMainFrame() && req.hasGesture() && trusted(Uri.parse(view.getUrl())) && "scan".equals(uri.getHost())) {
                        try {
                            int count = Integer.parseInt(uri.getQueryParameter("count"));
                            String token = uri.getQueryParameter("token");
                            if (count > 0 && count <= 1000 && token != null && token.matches("[a-zA-Z0-9-]{1,80}"))
                                choose(count, token);
                        } catch (NumberFormatException ignored) {}
                    }
                    return true;
                }
                return req.isForMainFrame() && !trusted(uri);
            }
        });
        web.loadUrl(HOME);
    }
    private void choose(int count, String token) {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        List<BluetoothDevice> readers = new ArrayList<>();
        if (adapter != null && adapter.isEnabled())
            for (BluetoothDevice d : adapter.getBondedDevices())
                if (d.getName() != null && d.getName().toUpperCase(Locale.ROOT).startsWith("RFD8500")) readers.add(d);
        if (readers.isEmpty()) {
            new AlertDialog.Builder(this).setMessage("Accendi il Bluetooth e associa la RFD8500 al palmare.").setPositiveButton("Chiudi",null).show();
        } else if (readers.size() == 1) scan(readers.get(0),count,token);
        else {
            String[] names = new String[readers.size()];
            for (int i=0;i<names.length;i++) names[i]=readers.get(i).getName();
            new AlertDialog.Builder(this).setTitle("Scegli la pistola").setItems(names,(d,i)->scan(readers.get(i),count,token)).show();
        }
    }
    private void closeSocket() {
        BluetoothSocket socket = active;
        active = null;
        if (socket != null) try { socket.close(); } catch(IOException ignored) {}
    }
    private static void send(BluetoothSocket socket,String command) throws IOException {
        OutputStream out = socket.getOutputStream();
        out.write((command+"\r\n").getBytes("US-ASCII"));
        out.flush();
    }
    private void scan(BluetoothDevice reader, int count, String token) {
        closeSocket();
        final int session = ++generation;
        AlertDialog progress = new AlertDialog.Builder(this).setTitle("Lettura RFID").setMessage("Collegamento alla pistola…")
            .setNegativeButton("Annulla",(d,i)->{generation++;closeSocket();}).setCancelable(false).show();
        final BluetoothSocket socket;
        try { socket=reader.createRfcommSocketToServiceRecord(RFID); active=socket; }
        catch(IOException e){progress.setMessage(e.getMessage());return;}
        Runnable timeout = ()->{if(session==generation)closeSocket();};
        handler.postDelayed(timeout,15000);
        new Thread(()->{
            Set<String> tags=new LinkedHashSet<>();
            String error=null;
            try {
                socket.connect();
                send(socket,"connect");
                BufferedReader input=new BufferedReader(new InputStreamReader(socket.getInputStream(),"US-ASCII"));
                boolean started=false;
                String line;
                while(tags.size()<count && (line=input.readLine())!=null) {
                    if(line.contains("Status:") && !line.contains("Status:OK") && !line.contains("Connection Successful"))
                        throw new IOException(line);
                    if(!started && line.contains("Connection Successful")) {
                        started=true;
                        send(socket,"inventory");
                        handler.removeCallbacks(timeout);
                        handler.postDelayed(timeout,120000);
                        runOnUiThread(()->{if(session==generation)progress.setMessage("Avvicina i capi · 0 / "+count);});
                    } else if(started) {
                        String[] fields=line.split(",",-1);
                        if(fields.length<3 || !line.startsWith(",,")) continue;
                        String epc=fields[2].trim().toUpperCase(Locale.ROOT);
                        if(epc.matches("(?:[0-9A-F]{2}){1,62}") && tags.add(epc)){
                            int n=tags.size();
                            runOnUiThread(()->{if(session==generation)progress.setMessage(n+" / "+count+" tag distinti");});
                        }
                    }
                }
                if(tags.size()<count)throw new IOException("Lettura incompleta");
            } catch(Exception e){error=e.getMessage();}
            finally {
                handler.removeCallbacks(timeout);
                try {send(socket,"abort");}catch(IOException ignored){}
                try {socket.close();}catch(IOException ignored){}
            }
            final String message=error;
            runOnUiThread(()->{
                if(session!=generation || isFinishing())return;
                active=null; progress.dismiss();
                if(message!=null){
                    new AlertDialog.Builder(this).setTitle("Lettura interrotta").setMessage(tags.size()+" / "+count+" tag. Chiudi eventuali altre app collegate alla pistola e riprova. "+message).setPositiveButton("Chiudi",null).show();
                } else if(web.getUrl()!=null && trusted(Uri.parse(web.getUrl()))) {
                    web.evaluateJavascript("window.dispatchEvent(new CustomEvent('mycro-rfid-result',{detail:{token:"+JSONObject.quote(token)+",tags:"+new JSONArray(tags).toString()+"}}))",null);
                }
            });
        }).start();
    }
    @Override public void onBackPressed(){if(web.canGoBack())web.goBack();else super.onBackPressed();}
    @Override public void onDestroy(){generation++;closeSocket();handler.removeCallbacksAndMessages(null);super.onDestroy();}
}
